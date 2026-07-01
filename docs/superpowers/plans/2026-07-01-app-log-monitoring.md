# App Log Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user opt individual monitored apps into CSV logging of their CPU/RAM/swap stats to a file, tapping the existing poll loop, so lags can be debugged after the fact.

**Architecture:** A new `ProcessLogWriterService` owns per-app CSV files under `~/Library/Application Support/ProcessMonitor/logs/`. `ProcessConfigStore` persists which app IDs have logging enabled. `ProcessMonitorService` calls the writer once per poll tick for each enabled, running app. `ProcessRowView`'s context menu and `SettingsView`'s `DefinitionRow` both expose a toggle, current file size (warning-colored past 10MB), Reveal-in-Finder, and Clear actions.

**Tech Stack:** Swift 5.9, SwiftPM package (`Package.swift`), SwiftUI, XCTest. macOS 13+ target.

## Global Constraints

- CSV columns, in order, exactly: `timestamp,cpu_percent,memory_mb,swap_mb,process_count`. Header row written once per file.
- Log files live at `~/Library/Application Support/ProcessMonitor/logs/<definitionID>.csv` — one file per app.
- 10MB (`10 * 1024 * 1024` bytes) is the size-warning threshold. **No automatic rotation or cap** — files grow until the user hits Clear.
- No new sampling/polling path — logging taps the stats `ProcessMonitorService` already computes each tick.
- All file I/O failures are silent no-ops (never crash, never block the poll loop) — same precedent as `ProcessConfigStore.persist()`.
- Spec: `docs/superpowers/specs/2026-07-01-app-log-monitoring-design.md` is the source of truth if anything here is ambiguous.
- **Build discipline:** if tasks are executed by sub-agents, each sub-agent implements and writes/runs its own unit tests with `swift test --filter <TestClass>` only (scoped to its own new test class). Do **not** run a full `swift build` or full `swift test` (whole suite) from a sub-agent — this package is a full SwiftPM cold build each time, and N sub-agents × full build is wasteful. The main agent runs one full `swift build && swift test` pass after all tasks are complete (Task 6).

---

### Task 1: ProcessLogWriterService (core file I/O)

**Files:**
- Create: `ProcessMonitor/Services/ProcessLogWriterService.swift`
- Test: `Tests/ProcessMonitorTests/ProcessLogWriterServiceTests.swift`

**Interfaces:**
- Consumes: `MonitoredProcess` (existing type — `ProcessMonitor/Models/MonitoredProcess.swift`), specifically `.definition.id: String`, `.status: ProcessStatus`, `.totalCPU: Double`, `.totalMemoryMB: Double`, `.totalSwapMB: Double`, `.children: [ProcessChild]`, `.rootPids: [pid_t]`.
- Produces (used by Tasks 3, 4, 5):
  - `final class ProcessLogWriterService`
  - `init(logsDirectory: URL = Self.defaultLogsDirectory())`
  - `func log(process: MonitoredProcess)`
  - `func fileSizeBytes(forAppID id: String) -> Int64?`
  - `func clearLog(forAppID id: String)`
  - `func revealLog(forAppID id: String)`
  - `static let warningThresholdBytes: Int64`
  - `static func defaultLogsDirectory() -> URL`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ProcessMonitorTests/ProcessLogWriterServiceTests.swift`:

```swift
import XCTest
@testable import ProcessMonitor

final class ProcessLogWriterServiceTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PMLogWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeProcess(
        id: String = "cursor",
        status: ProcessStatus = .running,
        cpu: Double = 12.3,
        memoryMB: Double = 256.7,
        swapMB: Double = 1.2,
        childCount: Int = 2
    ) -> MonitoredProcess {
        let definition = ProcessDefinition(
            id: id, displayName: id, patterns: [id], defaultLimitMB: 1024
        )
        let children: [ProcessChild] = (0..<childCount).map {
            ProcessChild(id: pid_t(1000 + $0), parentPid: 1, command: "child\($0)", memoryMB: 10, swapMB: 0, cpuPercent: 1)
        }
        return MonitoredProcess(
            id: id,
            definition: definition,
            status: status,
            rootPids: [999],
            totalMemoryMB: memoryMB,
            totalSwapMB: swapMB,
            totalCPU: cpu,
            memoryHistory: [],
            cpuHistory: [],
            children: children,
            memoryLimitMB: 1024,
            appBundlePath: nil,
            startedBy: nil
        )
    }

    func testLogCreatesFileWithHeaderAndFirstRow() {
        let writer = ProcessLogWriterService(logsDirectory: tempDir)
        writer.log(process: makeProcess())

        let fileURL = tempDir.appendingPathComponent("cursor.csv")
        let contents = try! String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "timestamp,cpu_percent,memory_mb,swap_mb,process_count")
        XCTAssertTrue(lines[1].hasSuffix(",12.3,256.7,1.2,3"))
    }

    func testSecondLogAppendsWithoutRepeatingHeader() {
        let writer = ProcessLogWriterService(logsDirectory: tempDir)
        writer.log(process: makeProcess())
        writer.log(process: makeProcess())

        let fileURL = tempDir.appendingPathComponent("cursor.csv")
        let contents = try! String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "timestamp,cpu_percent,memory_mb,swap_mb,process_count")
    }

    func testFileSizeBytesNilBeforeWriteNonNilAfter() {
        let writer = ProcessLogWriterService(logsDirectory: tempDir)
        XCTAssertNil(writer.fileSizeBytes(forAppID: "cursor"))

        writer.log(process: makeProcess())
        XCTAssertNotNil(writer.fileSizeBytes(forAppID: "cursor"))
    }

    func testClearLogTruncatesToHeaderOnly() {
        let writer = ProcessLogWriterService(logsDirectory: tempDir)
        writer.log(process: makeProcess())
        writer.log(process: makeProcess())
        let sizeBeforeClear = writer.fileSizeBytes(forAppID: "cursor")!

        writer.clearLog(forAppID: "cursor")
        let sizeAfterClear = writer.fileSizeBytes(forAppID: "cursor")!

        XCTAssertLessThan(sizeAfterClear, sizeBeforeClear)

        let fileURL = tempDir.appendingPathComponent("cursor.csv")
        let contents = try! String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(contents, "timestamp,cpu_percent,memory_mb,swap_mb,process_count\n")
    }

    func testLogNoOpWhenNotRunning() {
        let writer = ProcessLogWriterService(logsDirectory: tempDir)
        writer.log(process: makeProcess(status: .notRunning))

        XCTAssertNil(writer.fileSizeBytes(forAppID: "cursor"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ProcessLogWriterServiceTests`
Expected: FAIL to compile — `ProcessLogWriterService` does not exist yet.

- [ ] **Step 3: Implement ProcessLogWriterService**

Create `ProcessMonitor/Services/ProcessLogWriterService.swift`:

```swift
import Foundation
import AppKit

/// Appends one CSV row per poll tick for apps the user has opted into
/// file logging, to help debug lags after the fact. One file per app,
/// under ~/Library/Application Support/ProcessMonitor/logs/. No rotation —
/// the UI surfaces a 10MB warning and a manual Clear action instead.
final class ProcessLogWriterService {
    static let warningThresholdBytes: Int64 = 10 * 1024 * 1024 // 10 MB

    private static let header = "timestamp,cpu_percent,memory_mb,swap_mb,process_count\n"

    private let logsDirectory: URL
    private var fileHandles: [String: FileHandle] = [:]
    private let dateFormatter = ISO8601DateFormatter()
    private let queue = DispatchQueue(label: "com.cristianofagundes.ProcessMonitor.logwriter")

    init(logsDirectory: URL = Self.defaultLogsDirectory()) {
        self.logsDirectory = logsDirectory
    }

    func log(process: MonitoredProcess) {
        guard process.status != .notRunning else { return }
        let timestamp = dateFormatter.string(from: Date())
        let processCount = process.children.count + process.rootPids.count
        let line = String(
            format: "%@,%.1f,%.1f,%.1f,%d\n",
            timestamp, process.totalCPU, process.totalMemoryMB, process.totalSwapMB, processCount
        )
        queue.sync {
            appendLine(line, forAppID: process.definition.id)
        }
    }

    func fileSizeBytes(forAppID id: String) -> Int64? {
        queue.sync {
            let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL(forAppID: id).path)
            return attrs?[.size] as? Int64
        }
    }

    func clearLog(forAppID id: String) {
        queue.sync {
            fileHandles[id]?.closeFile()
            fileHandles[id] = nil
            writeHeaderOnlyFile(forAppID: id)
        }
    }

    func revealLog(forAppID id: String) {
        let url = fileURL(forAppID: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func defaultLogsDirectory() -> URL {
        let fm = FileManager.default
        let base: URL
        if let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            base = appSupport
        } else {
            base = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        }
        return base
            .appendingPathComponent("ProcessMonitor", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }

    // MARK: - Private

    private func fileURL(forAppID id: String) -> URL {
        logsDirectory.appendingPathComponent("\(id).csv")
    }

    private func appendLine(_ line: String, forAppID id: String) {
        guard let handle = fileHandles[id] ?? openOrCreateHandle(forAppID: id) else { return }
        guard let data = line.data(using: .utf8) else { return }
        handle.seekToEndOfFile()
        try? handle.write(contentsOf: data)
    }

    private func openOrCreateHandle(forAppID id: String) -> FileHandle? {
        let url = fileURL(forAppID: id)
        if !FileManager.default.fileExists(atPath: url.path) {
            writeHeaderOnlyFile(forAppID: id)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        fileHandles[id] = handle
        return handle
    }

    private func writeHeaderOnlyFile(forAppID id: String) {
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: fileURL(forAppID: id).path,
            contents: Self.header.data(using: .utf8)
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ProcessLogWriterServiceTests`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add ProcessMonitor/Services/ProcessLogWriterService.swift Tests/ProcessMonitorTests/ProcessLogWriterServiceTests.swift
git commit -m "feat(logging): add ProcessLogWriterService for per-app CSV stat logs"
```

---

### Task 2: ProcessConfigStore — persisted logging toggle

**Files:**
- Modify: `ProcessMonitor/Stores/ProcessConfigStore.swift`
- Test: `Tests/ProcessMonitorTests/ProcessConfigStoreTests.swift`

**Interfaces:**
- Consumes: nothing new from other tasks.
- Produces (used by Tasks 3, 4, 5):
  - `@Published var loggingEnabledIDs: Set<String>` on `ProcessConfigStore`
  - `func isLoggingEnabled(for definitionId: String) -> Bool`
  - `func setLoggingEnabled(_ enabled: Bool, for definitionId: String)`
  - `removeDefinition(id:)` also removes the id from `loggingEnabledIDs`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/ProcessMonitorTests/ProcessConfigStoreTests.swift`, inside the existing `ProcessConfigStoreTests` class, reusing its existing `tempDir` property and `makeStore() -> ProcessConfigStore` helper:

```swift
    func testLoggingToggleDefaultsToDisabledAndPersists() {
        let store = makeStore()
        XCTAssertFalse(store.isLoggingEnabled(for: "cursor"))

        store.setLoggingEnabled(true, for: "cursor")
        XCTAssertTrue(store.isLoggingEnabled(for: "cursor"))

        store.setLoggingEnabled(false, for: "cursor")
        XCTAssertFalse(store.isLoggingEnabled(for: "cursor"))
    }

    func testRemoveDefinitionClearsLoggingToggle() {
        let store = makeStore()
        store.setLoggingEnabled(true, for: "cursor")
        XCTAssertTrue(store.isLoggingEnabled(for: "cursor"))

        store.removeDefinition(id: "cursor")
        XCTAssertFalse(store.isLoggingEnabled(for: "cursor"))
    }

    func testLoggingToggleSurvivesReload() {
        let fileURL = tempDir.appendingPathComponent("config.json")
        let suiteName = "test.\(UUID().uuidString)"
        let first = ProcessConfigStore(configFileURL: fileURL, defaults: UserDefaults(suiteName: suiteName)!)
        first.setLoggingEnabled(true, for: "java")

        let second = ProcessConfigStore(configFileURL: fileURL, defaults: UserDefaults(suiteName: suiteName)!)
        XCTAssertTrue(second.isLoggingEnabled(for: "java"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ProcessConfigStoreTests`
Expected: FAIL to compile — `isLoggingEnabled`/`setLoggingEnabled` don't exist yet.

- [ ] **Step 3: Implement the store changes**

In `ProcessMonitor/Stores/ProcessConfigStore.swift`:

1. Add the published property, right after the `diskVolumes` property (after line 57, `}`):

```swift
    @Published var loggingEnabledIDs: Set<String> = [] {
        didSet { if isInitialized { persist() } }
    }
```

2. Add the field to `PersistedConfig` (after `notificationRateLimitSeconds: Double?` inside the struct):

```swift
        var loggingEnabledIDs: Set<String>?
```

3. In `init(configFileURL:defaults:)`, in the `if let loaded = ...` branch (after `self.autoRestartLimits = loaded.autoRestartLimits ?? [:]`), add:

```swift
            self.loggingEnabledIDs = loaded.loggingEnabledIDs ?? []
```

4. In the `else` (UserDefaults migration) branch, after `self.autoRestartLimits = [:]`, add:

```swift
            self.loggingEnabledIDs = []
```

5. Add helper methods near `// MARK: - Auto-restart Limits` (a new `// MARK: - Logging` section works well right after it):

```swift
    // MARK: - Logging

    func isLoggingEnabled(for definitionId: String) -> Bool {
        loggingEnabledIDs.contains(definitionId)
    }

    func setLoggingEnabled(_ enabled: Bool, for definitionId: String) {
        if enabled {
            loggingEnabledIDs.insert(definitionId)
        } else {
            loggingEnabledIDs.remove(definitionId)
        }
    }
```

6. In `removeDefinition(id:)`, add the cleanup line:

```swift
    func removeDefinition(id: String) {
        definitions.removeAll { $0.id == id }
        limits.removeValue(forKey: id)
        loggingEnabledIDs.remove(id)
    }
```

7. In `persist()`, add the field to the `PersistedConfig(...)` construction:

```swift
            notificationRateLimitSeconds: notificationRateLimitSeconds,
            loggingEnabledIDs: loggingEnabledIDs
```

(match this to wherever `notificationRateLimitSeconds` currently sits as the last argument in that initializer call — add `loggingEnabledIDs` right after it.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ProcessConfigStoreTests`
Expected: PASS (all existing tests + 3 new ones)

- [ ] **Step 5: Commit**

```bash
git add ProcessMonitor/Stores/ProcessConfigStore.swift Tests/ProcessMonitorTests/ProcessConfigStoreTests.swift
git commit -m "feat(logging): persist per-app file-logging toggle in ProcessConfigStore"
```

---

### Task 3: Wire ProcessLogWriterService into the poll loop

**Files:**
- Modify: `ProcessMonitor/Services/ProcessMonitorService.swift`
- Test: `Tests/ProcessMonitorTests/ProcessMonitorServiceExtraTests.swift`

**Interfaces:**
- Consumes:
  - `ProcessLogWriterService` (Task 1): `init(logsDirectory:)`, `func log(process:)`, `func fileSizeBytes(forAppID:)`
  - `ProcessConfigStore.loggingEnabledIDs` / `isLoggingEnabled(for:)` (Task 2)
- Produces (used by Tasks 4, 5):
  - `ProcessMonitorService.logWriter: ProcessLogWriterService` (public stored property, readable by views)
  - `ProcessMonitorService.init(..., logWriter: ProcessLogWriterService = ProcessLogWriterService())` — new trailing param, default-constructible so existing call sites in `ProcessMonitorApp.swift` and other tests don't need changes.

- [ ] **Step 1: Write the failing test**

Add to `Tests/ProcessMonitorTests/ProcessMonitorServiceExtraTests.swift` (append inside the existing test class, reusing its `makeConfig()`/`dummyFactory`/`pollUntil` helpers already in that file):

```swift
    func testLogsOnlyEnabledRunningProcesses() throws {
        let logsDir = tempDir.appendingPathComponent("logs", isDirectory: true)
        let logWriter = ProcessLogWriterService(logsDirectory: logsDir)
        let config = makeConfig()
        config.setLoggingEnabled(true, for: "java") // "cursor" stays disabled

        let entries: [RawProcessEntry] = [
            RawProcessEntry(pid: 9990, ppid: 1, rssKB: 0, cpuPercent: 5, command: "/usr/bin/java"),
            RawProcessEntry(pid: 9991, ppid: 1, rssKB: 0, cpuPercent: 5, command: "/Applications/Cursor.app/Contents/MacOS/Cursor")
        ]

        let service = ProcessMonitorService(
            configStore: config,
            notificationService: NotificationService(isHosted: false),
            pollInterval: 3600,
            processEntriesProvider: { entries },
            pollPublisherFactory: dummyFactory,
            logWriter: logWriter
        )
        service.refresh()
        pollUntil { logWriter.fileSizeBytes(forAppID: "java") != nil }

        XCTAssertNotNil(logWriter.fileSizeBytes(forAppID: "java"))
        XCTAssertNil(logWriter.fileSizeBytes(forAppID: "cursor"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProcessMonitorServiceExtraTests/testLogsOnlyEnabledRunningProcesses`
Expected: FAIL to compile — `ProcessMonitorService.init` has no `logWriter:` parameter yet.

- [ ] **Step 3: Wire the service**

In `ProcessMonitor/Services/ProcessMonitorService.swift`:

1. Add a stored property, right after `private let notificationService: NotificationService` (line 35):

```swift
    let logWriter: ProcessLogWriterService
```

2. Add the init parameter and assignment. Change the `init` signature (lines 44-50) to:

```swift
    init(
        configStore: ProcessConfigStore = ProcessConfigStore(),
        notificationService: NotificationService = NotificationService(),
        pollInterval: TimeInterval? = nil,
        processEntriesProvider: ProcessEntriesProvider? = nil,
        pollPublisherFactory: PollPublisherFactory? = nil,
        logWriter: ProcessLogWriterService = ProcessLogWriterService()
    ) {
```

and add this line inside the init body, alongside the other assignments (after `self.notificationService = notificationService`, line 52):

```swift
        self.logWriter = logWriter
```

3. Add a private helper method, near `checkMemoryLimits` (e.g. right before it):

```swift
    /// Appends one CSV row per app the user has opted into file logging,
    /// skipping apps that aren't currently running. Runs on the same
    /// background context as the rest of the tick so file I/O never
    /// touches the main thread.
    private func writeLogs(for processes: [MonitoredProcess]) {
        for process in processes where configStore.loggingEnabledIDs.contains(process.definition.id) {
            guard process.status != .notRunning else { continue }
            logWriter.log(process: process)
        }
    }
```

4. Call it from both tick paths, on the background thread, right after `grouped` is computed and before dispatching to main:

In `refresh()` (the `pollPublisherFactory != nil` branch, inside the `DispatchQueue.global(qos: .userInitiated).async` block), after the line `let grouped = self.buildGroupedProcesses(from: rawEntries)`, add:

```swift
                self.writeLogs(for: grouped)
```

In `refreshAsync()`, after the line `let grouped = self.buildGroupedProcesses(from: rawEntries)`, add:

```swift
        self.writeLogs(for: grouped)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProcessMonitorServiceExtraTests/testLogsOnlyEnabledRunningProcesses`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ProcessMonitor/Services/ProcessMonitorService.swift Tests/ProcessMonitorTests/ProcessMonitorServiceExtraTests.swift
git commit -m "feat(logging): write per-app CSV logs from the poll loop when enabled"
```

---

### Task 4: Process row context menu (Log to File / size / Reveal / Clear)

**Files:**
- Modify: `ProcessMonitor/Views/ProcessRowView.swift`
- Modify: `ProcessMonitor/Views/ProcessListView.swift:409-450` (the `processList` computed property, where `ProcessRowView` is instantiated)

**Interfaces:**
- Consumes:
  - `ProcessLogWriterService` (Task 1): `func fileSizeBytes(forAppID:) -> Int64?`, `func revealLog(forAppID:)`, `func clearLog(forAppID:)`, `static let warningThresholdBytes: Int64`
  - `ProcessConfigStore.isLoggingEnabled(for:)` / `setLoggingEnabled(_:for:)` (Task 2)
  - `ProcessMonitorService.logWriter` (Task 3)
  - `formatMemory(_ mb: Double) -> String` (existing, `ProcessMonitor/Models/ProcessChild.swift:48`)
- Produces: no new public API — this is a leaf UI task. (Task 5 does the equivalent for Settings independently.)

This is UI-only; there's no meaningful unit test for a SwiftUI context menu closure — verify by building and manually checking (folded into Task 6's manual check).

- [ ] **Step 1: Add new parameters to ProcessRowView**

In `ProcessMonitor/Views/ProcessRowView.swift`, add three stored properties right after the existing ones (after line 9, `let onKillChild: (pid_t) -> Void`):

```swift
    let logWriter: ProcessLogWriterService
    let isLoggingEnabled: Bool
    let onToggleLogging: (Bool) -> Void
```

- [ ] **Step 2: Add the context menu**

In the `mainRow` computed property, add `.contextMenu { contextMenuContent }` to the modifier chain — right after `.onTapGesture { ... }` closes (after line 50, before the closing `}` of `mainRow`'s body at line 51):

```swift
        .onTapGesture {
            guard process.status != .notRunning, !process.childGroups.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                isExpanded.toggle()
            }
        }
        .contextMenu {
            contextMenuContent
        }
```

Then add the menu content as a new computed property (place it in a new `// MARK: - Context Menu` section, right after the `mainRow` property block ends):

```swift
    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            onToggleLogging(!isLoggingEnabled)
        } label: {
            Label(
                NSLocalizedString("Log to File", comment: "Context menu: enable/disable file logging"),
                systemImage: isLoggingEnabled ? "checkmark.square" : "square"
            )
        }

        if let bytes = logWriter.fileSizeBytes(forAppID: process.definition.id) {
            Divider()

            let isOverThreshold = bytes >= ProcessLogWriterService.warningThresholdBytes
            Text(String(
                format: NSLocalizedString("Log size: %@", comment: "Context menu: current log file size"),
                formatMemory(Double(bytes) / 1_048_576)
            ))
            if isOverThreshold {
                Label(
                    NSLocalizedString("Log file is large", comment: "Context menu: log file over 10MB warning"),
                    systemImage: "exclamationmark.triangle.fill"
                )
            }

            Button {
                logWriter.revealLog(forAppID: process.definition.id)
            } label: {
                Label(NSLocalizedString("Reveal Log", comment: "Context menu action"), systemImage: "folder")
            }

            Button {
                logWriter.clearLog(forAppID: process.definition.id)
            } label: {
                Label(NSLocalizedString("Clear Log", comment: "Context menu action"), systemImage: "trash")
            }
        }
    }
```

(SwiftUI rebuilds `contextMenuContent` fresh every time the menu is opened, so reading `logWriter.fileSizeBytes` directly here — with no `@State` — always reflects the current file size with no manual refresh logic needed.)

- [ ] **Step 3: Wire the new parameters at the call site**

In `ProcessMonitor/Views/ProcessListView.swift`, in the `processList` computed property, update the `ProcessRowView(...)` call (around line 432) to:

```swift
                            ProcessRowView(
                                process: process,
                                onKillGroup: { monitorService.killGroup(process) },
                                onRestart: { monitorService.restartGroup(process) },
                                onKillChildGroup: { pids in monitorService.killProcesses(pids: pids) },
                                onKillChild: { pid in monitorService.killProcess(pid: pid) },
                                logWriter: monitorService.logWriter,
                                isLoggingEnabled: configStore.isLoggingEnabled(for: process.definition.id),
                                onToggleLogging: { configStore.setLoggingEnabled($0, for: process.definition.id) }
                            )
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 5: Commit**

```bash
git add ProcessMonitor/Views/ProcessRowView.swift ProcessMonitor/Views/ProcessListView.swift
git commit -m "feat(logging): add Log to File / size / Reveal / Clear to the process row context menu"
```

---

### Task 5: Settings row (Log to File toggle / size pill / Reveal / Clear)

**Files:**
- Modify: `ProcessMonitor/Views/SettingsView.swift` (`SettingsView` struct and `DefinitionRow` struct)
- Modify: `ProcessMonitor/Views/SettingsWindowController.swift`
- Modify: `ProcessMonitor/Views/ProcessListView.swift` (the `SettingsWindowController.shared.open(...)` call site, around line 309)

**Interfaces:**
- Consumes:
  - `ProcessLogWriterService` (Task 1): `func fileSizeBytes(forAppID:) -> Int64?`, `func revealLog(forAppID:)`, `func clearLog(forAppID:)`, `static let warningThresholdBytes: Int64`
  - `ProcessConfigStore.isLoggingEnabled(for:)` / `setLoggingEnabled(_:for:)` (Task 2)
  - `ProcessMonitorService.logWriter` (Task 3)
  - `formatMemory(_ mb: Double) -> String` (existing)
- Produces: no new public API — leaf UI task.

This is UI-only; verify by building and the manual check in Task 6.

- [ ] **Step 1: Thread `logWriter` through SettingsWindowController**

In `ProcessMonitor/Views/SettingsWindowController.swift`, add a parameter to `open(...)`:

```swift
    func open(
        configStore: ProcessConfigStore,
        launchAtLoginStore: LaunchAtLoginStore,
        diskMonitorService: DiskMonitorService,
        cleanupStore: CleanupStore,
        logWriter: ProcessLogWriterService
    ) {
```

and pass it to `SettingsView`:

```swift
        let settingsView = SettingsView(
            configStore: configStore,
            launchAtLoginStore: launchAtLoginStore,
            diskMonitorService: diskMonitorService,
            cleanupStore: cleanupStore,
            logWriter: logWriter
        )
```

- [ ] **Step 2: Update the call site in ProcessListView**

In `ProcessMonitor/Views/ProcessListView.swift`, update the `SettingsWindowController.shared.open(...)` call (around line 309):

```swift
                    action: {
                        SettingsWindowController.shared.open(
                            configStore: configStore,
                            launchAtLoginStore: launchAtLoginStore,
                            diskMonitorService: diskMonitorService,
                            cleanupStore: cleanupStore,
                            logWriter: monitorService.logWriter
                        )
                    }
```

- [ ] **Step 3: Add `logWriter` to SettingsView and thread it to DefinitionRow**

In `ProcessMonitor/Views/SettingsView.swift`, add a stored property to `SettingsView` right after `@ObservedObject var cleanupStore: CleanupStore` (line 147):

```swift
    let logWriter: ProcessLogWriterService
```

Update the `DefinitionRow(...)` instantiation inside `processesDetail` (around line 246):

```swift
                        DefinitionRow(
                            definition: def,
                            currentLimit: configStore.limit(for: def.id),
                            autoRestartLimit: configStore.autoRestartLimit(for: def.id),
                            isLoggingEnabled: configStore.isLoggingEnabled(for: def.id),
                            onLimitChanged: { configStore.setLimit($0, for: def.id) },
                            onAutoRestartChanged: { configStore.setAutoRestartLimit($0, for: def.id) },
                            onLoggingToggled: { configStore.setLoggingEnabled($0, for: def.id) },
                            onRemove: { configStore.removeDefinition(id: def.id) },
                            logWriter: logWriter
                        )
```

- [ ] **Step 4: Add the logging row to DefinitionRow**

In `ProcessMonitor/Views/SettingsView.swift`, add stored properties to `DefinitionRow` (after `let onRemove: () -> Void`, around line 620):

```swift
    let isLoggingEnabled: Bool
    let onLoggingToggled: (Bool) -> Void
    let logWriter: ProcessLogWriterService
```

Add local state (after `@State private var autoRestartMB: Double = 0`, around line 625):

```swift
    @State private var loggingEnabled: Bool = false
    @State private var logFileSizeBytes: Int64? = nil
```

In the `.onAppear { ... }` block (around lines 730-738), add:

```swift
        .onAppear {
            limitMB = Double(currentLimit)
            if let auto = autoRestartLimit {
                autoRestartEnabled = true
                autoRestartMB = Double(auto)
            } else {
                autoRestartMB = Double(currentLimit) * 1.5
            }
            loggingEnabled = isLoggingEnabled
            logFileSizeBytes = logWriter.fileSizeBytes(forAppID: definition.id)
        }
```

Add the new row inside the `VStack(spacing: 6) { ... }` block that already holds `limitSliderRow` and the auto-restart `HStack` (right after the auto-restart `if definition.isRestartable { ... }` block closes, around line 724, still inside the same `VStack`):

```swift
                HStack(spacing: 8) {
                    Label(NSLocalizedString("Log to File", comment: ""), systemImage: "doc.text")
                        .labelStyle(SettingsLabelStyle())
                        .font(.caption)
                    Spacer()
                    if let bytes = logFileSizeBytes {
                        let isOverThreshold = bytes >= ProcessLogWriterService.warningThresholdBytes
                        Text(formatMemory(Double(bytes) / 1_048_576))
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill((isOverThreshold ? Color.orange : Color.secondary).opacity(0.12)))
                            .foregroundStyle(isOverThreshold ? .orange : .secondary)

                        Button(NSLocalizedString("Reveal", comment: "")) {
                            logWriter.revealLog(forAppID: definition.id)
                        }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                        Button(NSLocalizedString("Clear", comment: "")) {
                            logWriter.clearLog(forAppID: definition.id)
                            logFileSizeBytes = logWriter.fileSizeBytes(forAppID: definition.id)
                        }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Toggle("", isOn: $loggingEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .onChange(of: loggingEnabled) { enabled in
                            onLoggingToggled(enabled)
                        }
                }
```

- [ ] **Step 5: Build to verify it compiles**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 6: Commit**

```bash
git add ProcessMonitor/Views/SettingsView.swift ProcessMonitor/Views/SettingsWindowController.swift ProcessMonitor/Views/ProcessListView.swift
git commit -m "feat(logging): add Log to File toggle, size pill, Reveal and Clear to Settings"
```

---

### Task 6: Full build, full test suite, manual check

**Files:** none (verification only).

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: all tests pass, including the new `ProcessLogWriterServiceTests` and the new methods added to `ProcessConfigStoreTests` / `ProcessMonitorServiceExtraTests`.

- [ ] **Step 2: Full release build**

Run: `swift build -c release`
Expected: builds with no errors or warnings introduced by this feature.

- [ ] **Step 3: Manual smoke test**

Run the app (`swift run ProcessMonitor` or launch the built `.app`), then:
1. Right-click a running monitored app in the popover list → confirm "Log to File" toggles, and after enabling, waiting a few poll ticks, and right-clicking again, "Log size" appears and grows.
2. Click "Reveal Log" → Finder opens with the app's `<id>.csv` selected inside `~/Library/Application Support/ProcessMonitor/logs/`. Open it and confirm the header row + one row per tick with sane CPU/RAM/swap numbers.
3. Open Settings → Processes tab → confirm the same toggle/size/Reveal/Clear controls work there and stay in sync (toggle it off in Settings, confirm the context menu in the main popover reflects it disabled).
4. Click "Clear" (either surface) → confirm the file's size drops back to header-only.
5. Quit and relaunch the app → confirm the logging toggle for that app is still enabled (persistence).

- [ ] **Step 4: Commit (only if Step 3 required fixes)**

If manual testing surfaced any fix, commit it separately with a message describing the fix. If no fixes were needed, skip this step — there's nothing to commit.
