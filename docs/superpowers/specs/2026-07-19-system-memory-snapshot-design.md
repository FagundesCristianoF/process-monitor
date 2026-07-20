# System Memory Snapshot — Design Spec

**Date:** 2026-07-19
**Status:** Approved

## Problem

`ProcessMonitorService` only reports RAM for processes the user has explicitly
added to their watch list. With 14GB of swap in use, the user needs to see
which processes — including ones never added to ProcessMonitor — are
consuming the most memory system-wide, to identify the culprit.

## Scope

On-demand top-10 system-wide RAM report, view-only, ranked by physical memory
footprint. No continuous/live scanning, no new window, no "add to watch"
action from the report. Triggered from the existing system memory row in the
popover.

## Data Source

`fetchProcessEntries()` (`ProcessMonitorService.swift:242`) already enumerates
every PID on the system via `proc_listpids(PROC_ALL_PIDS, …)` and captures
`pid`/`ppid`/`command`/`cpuPercent` for each — today only used to build the
watched-process groups. `processMemoryUsage(for:fallbackRssKB:)`
(`ProcessMonitorService.swift:517`) already computes `footprintMB`/`swapMB`
per PID via `proc_pid_rusage`. Both are reused as-is; no new low-level
sampling code.

## Model

New struct in `ProcessMonitor/Models/ProcessChild.swift` (alongside the
existing `RawProcessEntry` / `formatMemory`):

```swift
struct SystemMemoryUser: Identifiable {
    let id: pid_t
    var pid: pid_t { id }
    let name: String       // last path component of RawProcessEntry.command
    let footprintMB: Double
}
```

## ProcessMonitorService

```swift
@Published var systemMemorySnapshot: [SystemMemoryUser] = []
@Published var isScanningSystemMemory: Bool = false

func scanSystemMemory(limit: Int = 10) {
    isScanningSystemMemory = true
    Task.detached(priority: .utility) { [weak self] in
        guard let self else { return }
        let entries = self.processEntriesProvider?() ?? self.fetchProcessEntries()
        let users = entries
            .map { entry -> SystemMemoryUser in
                let usage = self.processMemoryUsage(for: entry.pid, fallbackRssKB: entry.rssKB)
                let name = (entry.command as NSString).lastPathComponent
                return SystemMemoryUser(id: entry.pid, name: name, footprintMB: usage.footprintMB)
            }
            .filter { $0.footprintMB > 0 }
            .sorted { $0.footprintMB > $1.footprintMB }
            .prefix(limit)
        await MainActor.run {
            self.systemMemorySnapshot = Array(users)
            self.isScanningSystemMemory = false
        }
    }
}
```

- Same `Task.detached(priority: .utility)` + `MainActor.run` pattern as
  `refreshAsync()` — full-system scan (few hundred PIDs, one `proc_pid_rusage`
  call each) runs off the main thread.
- Independent of the poll loop/timer — only runs when triggered, no change to
  `refresh()`/`refreshAsync()`/`applyPollInterval`.
- `processMemoryUsage` stays `private` — `scanSystemMemory` is a method on
  the same `ProcessMonitorService`, no visibility change needed.

## Error Handling

PIDs owned by other users or protected by SIP/root fail `proc_pid_rusage` →
`processMemoryUsage` returns `footprintMB: 0` via the existing fallback path
→ excluded by `.filter { $0.footprintMB > 0 }`. No permission prompts, no
error surfaced to the user — matches existing fallback behavior. No new
entitlements required (`proc_listpids`/`proc_pid_rusage` are already called
today for the per-app view).

## UI (`ProcessListView.swift`)

`SystemMemoryRow` (line 44) gains a trailing disclosure button
(`chevron.down`/`chevron.up`, rotates on toggle — same idiom as existing
expand affordances in the codebase). Tapping it:

1. Toggles a local `@State private var isSystemSnapshotExpanded: Bool` in
   `ProcessListView`.
2. On expand, if `monitorService.systemMemorySnapshot` is empty, calls
   `monitorService.scanSystemMemory()`.
3. While `isScanningSystemMemory`, shows a small centered `ProgressView()`
   under the row.
4. Once populated, shows up to 10 rows (`name` + `formatMemory(footprintMB)`),
   same row styling/font as existing compact rows (`.caption2`, secondary
   text color for the value) — no icons, no per-row actions.
5. Collapsing hides the list but keeps `systemMemorySnapshot` cached (no
   re-scan on re-expand); only a fresh tap of a "refresh" affordance
   (small `arrow.clockwise` button next to the disclosure chevron) re-runs
   `scanSystemMemory()`.

This lives inside `memorySection`, directly under the existing RAM gauge —
no new popover section, no new window.

## Testing

New test in `Tests/ProcessMonitorTests/ProcessMonitorServiceExtraTests.swift`
(or a new `SystemMemorySnapshotTests.swift` if that file is already large),
using the existing `processEntriesProvider` injection point:

- Inject fake `RawProcessEntry` values for known PIDs.
- Assert `scanSystemMemory()` populates `systemMemorySnapshot` sorted desc by
  `footprintMB`.
- Assert result is capped at `limit` even when more entries are provided.
- Assert entries with `footprintMB == 0` (simulating permission failure) are
  excluded.

Since `processMemoryUsage` calls real `proc_pid_rusage` against the injected
`pid` values, tests should use real PIDs available in the test process (e.g.
`getpid()` for a nonzero-footprint case, and an out-of-range/invalid pid like
`999999` for the zero-footprint case) — same approach already implied by the
existing fallback-path design (no mockable syscall layer exists today).

## Out of Scope

- Live/continuous system-wide scanning tied to the poll loop.
- "Add to watch" action per report row.
- Separate window/report view.
- Per-process swap breakdown in the report (footprint only, per approved
  ranking choice).
- Icons per row (matches "view-only, name + RAM" scope).
