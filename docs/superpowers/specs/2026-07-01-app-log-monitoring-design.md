# App Log Monitoring — Design Spec

**Date:** 2026-07-01
**Status:** Approved

## Problem

User wants to debug lags in specific monitored apps (e.g. Cursor, Java, Gradle) by
recording CPU/RAM/swap history to a file over time, instead of only seeing the
live in-app sparkline (60-sample rolling window, lost on quit).

## Scope

Per-app opt-in logging of the stats `ProcessMonitorService` already computes
every poll tick, written to a CSV file per app. No new sampling path — this
taps the existing poll loop.

## Data & Persistence

`ProcessConfigStore` gains:

```swift
@Published var loggingEnabledIDs: Set<String> = []
```

- Persisted in `PersistedConfig` as an optional field (`Set<String>?`), defaulting to
  `[]` on decode from older config files — same optional-field migration pattern
  already used for `autoRestartLimits` / `diskVolumes`.
- Helpers on the store:
  - `isLoggingEnabled(for definitionId: String) -> Bool`
  - `setLoggingEnabled(_ enabled: Bool, for definitionId: String)`
- `removeDefinition(id:)` also removes the id from `loggingEnabledIDs`.

## ProcessLogWriterService

New file: `ProcessMonitor/Services/ProcessLogWriterService.swift`.

Responsibilities:
- Append one CSV line per poll tick for each app with logging enabled.
- Report current file size and clear a file on demand.

```swift
final class ProcessLogWriterService {
    static let warningThresholdBytes: Int64 = 10 * 1024 * 1024 // 10 MB

    init(logsDirectory: URL = Self.defaultLogsDirectory())

    /// Appends a CSV row for this process's current sample.
    /// No-op if process.status == .notRunning.
    func log(process: MonitoredProcess)

    /// Current size of the app's log file, nil if it doesn't exist yet.
    func fileSizeBytes(forAppID id: String) -> Int64?

    /// Truncates the app's log file back to just the header row.
    func clearLog(forAppID id: String)

    /// Reveals the app's log file in Finder. No-op if it doesn't exist.
    func revealLog(forAppID id: String)

    static func logFileURL(forAppID id: String) -> URL
    static func defaultLogsDirectory() -> URL // ~/Library/Application Support/ProcessMonitor/logs
}
```

- CSV columns: `timestamp,cpu_percent,memory_mb,swap_mb,process_count`
  - `timestamp`: ISO8601 (`ISO8601DateFormatter`)
  - `cpu_percent`: `process.totalCPU`, 1 decimal
  - `memory_mb`: `process.totalMemoryMB`, 1 decimal
  - `swap_mb`: `process.totalSwapMB`, 1 decimal
  - `process_count`: `process.children.count + process.rootPids.count`
- Header row (`timestamp,cpu_percent,memory_mb,swap_mb,process_count\n`) written once,
  the first time a given app's file is created (or recreated by `clearLog`).
- One `FileHandle` per app id, opened lazily on first `log(process:)` call, kept
  open for the service's lifetime (i.e. app lifetime) rather than
  opened/closed per line — avoids per-tick file-open overhead. `clearLog`
  closes and reopens the handle for that id.
- No file size cap / rotation — file grows until the user manually clears it.
  A UI warning at 10MB (see below) is the only safeguard.
- Directory created lazily (`createDirectory(withIntermediateDirectories: true)`)
  on first write.

## Wiring into ProcessMonitorService

`ProcessMonitorService` takes an injected `logWriter: ProcessLogWriterService`
(default `ProcessLogWriterService()`), same DI pattern as `notificationService`.

After each tick's `processes` array is assigned (both the `pollPublisherFactory`
path and `refreshAsync`), loop over the processes:

```swift
for process in grouped where configStore.loggingEnabledIDs.contains(process.definition.id) {
    guard process.status != .notRunning else { continue }
    logWriter.log(process: process)
}
```

This runs on the same background dispatch as the rest of the tick's work (file
I/O off the main thread), consistent with how the rest of `refresh`/`refreshAsync`
is structured.

## UI

### Context menu (`ProcessRowView`)

Add `.contextMenu` to the row (none exists today) with:
- **Log to File** — checkmark-style toggle button, calls
  `configStore.setLoggingEnabled(_:for:)`
- **Size: X.X MB** (only shown once a log file exists) — plain text, styled
  orange when `>= warningThresholdBytes`
- **Reveal Log** — disabled/absent until the file exists
- **Clear Log** — disabled/absent until the file exists

### Settings (`SettingsView` / `DefinitionRow`)

Add a row below the existing auto-restart row, styled the same way (label +
toggle, matching `Toggle("", isOn:)` + `.toggleStyle(.switch)` pattern already
used there):

- "Log to File" toggle
- When enabled and a file exists: size pill (same capsule style as the
  existing limit/auto-restart pills), orange background/text when over the
  10MB threshold, plus small "Reveal" and "Clear" buttons next to it.

Both surfaces read size via `logWriter.fileSizeBytes(forAppID:)` — call it
each time the row appears/refreshes (not live-polled continuously; checking
on-appear plus after Clear/toggle actions is sufficient, matches the
lazy-refresh feel of the rest of settings).

## Error Handling

- Directory/file creation failures: silently no-op (same precedent as
  `ProcessConfigStore.persist()` — logging is a debug aid, not critical
  functionality; must never crash or block the poll loop).
- `revealLog` / `clearLog` on a non-existent file: no-op.

## Testing

New `Tests/ProcessMonitorTests/ProcessLogWriterServiceTests.swift`, same
temp-directory DI pattern as `DiskMonitorServiceTests`:
- First `log(process:)` call creates the file with header + one data row.
- Second call appends a second row (header not repeated).
- `fileSizeBytes` returns nil before any write, non-nil after.
- `clearLog` truncates back to header-only; `fileSizeBytes` drops accordingly.
- `log(process:)` is a no-op when `process.status == .notRunning`.

## Out of Scope

- Automatic rotation/size cap (explicitly rejected — warning + manual Clear
  instead).
- JSON or other formats (CSV chosen).
- Combined/interleaved log file (per-app files chosen).
- Live in-app log viewer (Reveal in Finder is sufficient).
