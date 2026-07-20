# System Memory Snapshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user see the top 10 system-wide RAM consumers — including processes never added to ProcessMonitor's watch list — via an on-demand scan triggered from the existing system memory row.

**Architecture:** `ProcessMonitorService` gains `scanSystemMemory(limit:)`, which reuses the existing full-PID enumeration (`fetchProcessEntries()`) and per-PID memory sampling (`processMemoryUsage(for:fallbackRssKB:)`) that today only feed the watched-process view. No new sampling path. The popover's `SystemMemoryRow` gains a disclosure control; expanding it triggers the scan and shows the ranked list inline, directly under the RAM gauge.

**Tech Stack:** Swift 5.9, SwiftPM package (`Package.swift`), SwiftUI, XCTest. macOS 13+ target.

## Global Constraints

- On-demand only — no continuous/live scan tied to the poll loop or timer.
- Ranked by `footprintMB` (physical memory footprint) descending, capped at 10 results (default `limit: Int = 10`).
- Entries with `footprintMB == 0` (permission-denied PIDs, or padding beyond the requested limit) are excluded before capping.
- View-only: no "add to watch" action, no new window, no per-row actions beyond the list itself.
- Runs off the main thread via `Task.detached(priority: .utility)` + `MainActor.run`, matching the existing `refresh()`/`refreshAsync()` pattern in `ProcessMonitorService.swift`.
- Any new `NSLocalizedString` key MUST be added to `ProcessMonitor/Resources/Localizable.xcstrings` with all 5 existing locales (`en`, `pt-BR`, `es`, `fr`, `de`) in the same task that introduces it — this codebase has twice shipped features with catalog entries missing (see commits `16f6ce3`, `a54edbf`), silently falling back to English on non-English builds. Do not repeat that.
- Spec: `docs/superpowers/specs/2026-07-19-system-memory-snapshot-design.md` is the source of truth if anything here is ambiguous.
- **Build discipline:** if tasks are executed by sub-agents, each sub-agent implements and runs only its own new test(s) with `swift test --filter <TestClass>/<testName>`. Do not run a full `swift build` or full `swift test` (whole suite) from a sub-agent — this package is a full SwiftPM cold build each time. The main agent runs one full `swift build && swift test` pass after all tasks are complete (Task 3).

---

### Task 1: `SystemMemoryUser` model + `ProcessMonitorService.scanSystemMemory`

**Files:**
- Modify: `ProcessMonitor/Models/ProcessChild.swift` (add `SystemMemoryUser` struct)
- Modify: `ProcessMonitor/Services/ProcessMonitorService.swift:13-17` (add `@Published` properties), `ProcessMonitorService.swift:149` (add `scanSystemMemory` method after `refreshAsync()`)
- Test: `Tests/ProcessMonitorTests/ProcessMonitorServiceExtraTests.swift`

**Interfaces:**
- Consumes (existing, unchanged):
  - `RawProcessEntry` (`ProcessMonitor/Models/ProcessChild.swift:40`) — `pid: pid_t`, `ppid: pid_t`, `rssKB: Int`, `cpuPercent: Double`, `command: String`
  - `ProcessMonitorService.fetchProcessEntries() -> [RawProcessEntry]` (private, `ProcessMonitorService.swift:242`)
  - `ProcessMonitorService.processMemoryUsage(for pid: pid_t, fallbackRssKB: Int) -> MemoryUsage` (private, `ProcessMonitorService.swift:517`), where `MemoryUsage` (`ProcessMonitorService.swift:508`) has `footprintMB: Double` and `swapMB: Double`
  - `ProcessMonitorService.processEntriesProvider: ProcessEntriesProvider?` (injected test seam, `ProcessMonitorService.swift:37`)
  - `formatMemory(_ mb: Double) -> String` (`ProcessMonitor/Models/ProcessChild.swift:48`)
- Produces (used by Task 2):
  - `struct SystemMemoryUser: Identifiable` — `id: pid_t`, `name: String`, `footprintMB: Double`, `formattedMemory: String`
  - `ProcessMonitorService.systemMemorySnapshot: [SystemMemoryUser]` (`@Published`)
  - `ProcessMonitorService.isScanningSystemMemory: Bool` (`@Published`)
  - `ProcessMonitorService.scanSystemMemory(limit: Int = 10)`

- [ ] **Step 1: Add the `SystemMemoryUser` model**

Edit `ProcessMonitor/Models/ProcessChild.swift`, inserting after the `RawProcessEntry` struct (after line 46, before `func formatMemory`):

```swift
struct SystemMemoryUser: Identifiable {
    let id: pid_t
    let name: String
    let footprintMB: Double

    var formattedMemory: String {
        formatMemory(footprintMB)
    }
}
```

- [ ] **Step 2: Write the failing tests**

Append to `Tests/ProcessMonitorTests/ProcessMonitorServiceExtraTests.swift`, inside the `ProcessMonitorServiceExtraTests` class, just before the final closing `}`:

```swift

    // MARK: - System memory snapshot

    func testScanSystemMemoryPopulatesSortedFilteredSnapshot() {
        let realPid = getpid() // this test process — proc_pid_rusage always succeeds against it
        let deadPid: pid_t = 999_999 // no such process — proc_pid_rusage fails, footprintMB falls back to 0

        let entries: [RawProcessEntry] = [
            RawProcessEntry(pid: deadPid, ppid: 1, rssKB: 0, cpuPercent: 0, command: "/usr/bin/ghost"),
            RawProcessEntry(pid: realPid, ppid: 1, rssKB: 0, cpuPercent: 0, command: "/usr/bin/xctest")
        ]

        let service = ProcessMonitorService(
            configStore: makeConfig(),
            notificationService: NotificationService(isHosted: false),
            pollInterval: 3600,
            processEntriesProvider: { entries },
            pollPublisherFactory: dummyFactory
        )

        service.scanSystemMemory()
        pollUntil { !service.isScanningSystemMemory }

        XCTAssertEqual(service.systemMemorySnapshot.count, 1)
        XCTAssertEqual(service.systemMemorySnapshot.first?.id, realPid)
        XCTAssertEqual(service.systemMemorySnapshot.first?.name, "xctest")
        XCTAssertGreaterThan(service.systemMemorySnapshot.first?.footprintMB ?? 0, 0)
    }

    func testScanSystemMemoryCapsAtLimit() {
        let realPid = getpid()
        // All entries point at this test process's own real pid (only pid that's
        // guaranteed to yield a nonzero footprint without special privileges);
        // duplicate pids are fine here since this test is only checking the cap,
        // not per-process de-duplication (scanSystemMemory doesn't de-dup).
        let entries = (0..<15).map { i in
            RawProcessEntry(pid: realPid, ppid: 1, rssKB: 0, cpuPercent: 0, command: "/usr/bin/xctest\(i)")
        }
        let service = ProcessMonitorService(
            configStore: makeConfig(),
            notificationService: NotificationService(isHosted: false),
            pollInterval: 3600,
            processEntriesProvider: { entries },
            pollPublisherFactory: dummyFactory
        )

        service.scanSystemMemory(limit: 5)
        pollUntil { !service.isScanningSystemMemory }

        XCTAssertEqual(service.systemMemorySnapshot.count, 5)
    }
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter ProcessMonitorServiceExtraTests/testScanSystemMemoryPopulatesSortedFilteredSnapshot`
Expected: FAIL to compile — `scanSystemMemory`, `isScanningSystemMemory`, `systemMemorySnapshot` don't exist yet on `ProcessMonitorService`.

- [ ] **Step 4: Implement `scanSystemMemory`**

Edit `ProcessMonitor/Services/ProcessMonitorService.swift`. Add two `@Published` properties right after line 17 (`systemMemoryTotalMB`):

```swift
    /// Top-10 system-wide RAM report from the most recent on-demand scan
    /// (every PID on the system, not just watched apps).
    @Published var systemMemorySnapshot: [SystemMemoryUser] = []
    @Published var isScanningSystemMemory: Bool = false
```

Then add the method right after `refreshAsync()`'s closing brace (currently line 149, immediately before `func killProcess(pid: pid_t)`):

```swift
    /// On-demand system-wide RAM report. Scans every PID (not just watched
    /// apps), reusing the same enumeration and per-PID memory sampling the
    /// watched-process poll loop already uses. Independent of the poll timer.
    func scanSystemMemory(limit: Int = 10) {
        isScanningSystemMemory = true
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let entries = self.processEntriesProvider?() ?? self.fetchProcessEntries()
            let users = entries
                .map { entry in
                    SystemMemoryUser(
                        id: entry.pid,
                        name: (entry.command as NSString).lastPathComponent,
                        footprintMB: self.processMemoryUsage(for: entry.pid, fallbackRssKB: entry.rssKB).footprintMB
                    )
                }
                .filter { $0.footprintMB > 0 }
                .sorted { $0.footprintMB > $1.footprintMB }
            let top = Array(users.prefix(limit))
            await MainActor.run {
                self.systemMemorySnapshot = top
                self.isScanningSystemMemory = false
            }
        }
    }

```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ProcessMonitorServiceExtraTests/testScanSystemMemoryPopulatesSortedFilteredSnapshot`
Expected: PASS

Run: `swift test --filter ProcessMonitorServiceExtraTests/testScanSystemMemoryCapsAtLimit`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
rtk git add ProcessMonitor/Models/ProcessChild.swift ProcessMonitor/Services/ProcessMonitorService.swift Tests/ProcessMonitorTests/ProcessMonitorServiceExtraTests.swift
rtk git commit -m "$(cat <<'EOF'
feat(monitor): add on-demand system-wide RAM scan

scanSystemMemory() reuses the existing full-PID enumeration and
per-PID memory sampling to rank the top 10 RAM consumers across
the whole system, not just watched apps.
EOF
)"
```

---

### Task 2: Popover UI — expandable "Top Processes" list

**Files:**
- Modify: `ProcessMonitor/Views/ProcessListView.swift:47-113` (`SystemMemoryRow`), `ProcessListView.swift:208-210` (add `@State`), `ProcessListView.swift:458-463` (`memorySection`)
- Modify: `ProcessMonitor/Resources/Localizable.xcstrings` (new key: `"Top Processes"`)

**Interfaces:**
- Consumes (from Task 1): `ProcessMonitorService.systemMemorySnapshot: [SystemMemoryUser]`, `.isScanningSystemMemory: Bool`, `.scanSystemMemory(limit:)`; `SystemMemoryUser.formattedMemory: String`
- Produces: nothing consumed by later tasks (final UI task).

- [ ] **Step 1: Add expand state**

In `ProcessListView.swift`, in the `ProcessListView` struct's property list (after `@Namespace private var sortNamespace`, line 210):

```swift
    @State private var isSystemSnapshotExpanded = false
```

- [ ] **Step 2: Give `SystemMemoryRow` a disclosure control**

Replace the `SystemMemoryRow` struct (lines 47-113) with:

```swift
private struct SystemMemoryRow: View {
    let usedMB: Double
    let totalMB: Double
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "memorychip.fill")
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isWarning ? .orange : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Memory", comment: "System RAM label"))
                    .font(.system(.caption, weight: .medium))
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(.quaternary.opacity(0.5))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(barColor)
                            .frame(width: geo.size.width * usedFraction, height: 4)
                    }
                }
                .frame(height: 4)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: NSLocalizedString("%@ used", comment: "RAM used label. %@ = formatted size"), formatDiskGB(usedMB / 1024)))
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(isWarning ? .orange : .primary)
                    .monospacedDigit()
                Text(formatDiskGB(totalMB / 1024))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if isWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
            }

            Button(action: onToggleExpand) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeOut(duration: 0.18), value: isExpanded)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var usedFraction: Double {
        guard totalMB > 0 else { return 0 }
        return min(1, usedMB / totalMB)
    }

    private var isWarning: Bool { usedFraction > 0.9 }

    private var barColor: Color {
        let used = usedFraction
        if used > 0.9 { return .red }
        if used > 0.8 { return .orange }
        return Color.accentColor
    }
}
```

(Only change from the original: two new stored properties, `Button(action: onToggleExpand)` block added after the existing warning-icon block.)

- [ ] **Step 3: Add the snapshot list view**

Insert a new struct right after `SystemMemoryRow`'s closing brace (before the `// MARK: - Disk Volume Row` comment):

```swift

// MARK: - System Memory Snapshot

private struct SystemMemorySnapshotSection: View {
    let users: [SystemMemoryUser]
    let isScanning: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(NSLocalizedString("Top Processes", comment: "Section header for system-wide top RAM consumers"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isScanning {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            } else {
                ForEach(users) { user in
                    HStack {
                        Text(user.name)
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer()
                        Text(user.formattedMemory)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 7)
    }
}
```

- [ ] **Step 4: Wire it into `memorySection`**

Replace the `memorySection` computed property (lines 458-463):

```swift
    private var memorySection: some View {
        VStack(spacing: 0) {
            SystemMemoryRow(
                usedMB: monitorService.systemMemoryUsedMB,
                totalMB: monitorService.systemMemoryTotalMB,
                isExpanded: isSystemSnapshotExpanded,
                onToggleExpand: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSystemSnapshotExpanded.toggle()
                    }
                    if isSystemSnapshotExpanded && monitorService.systemMemorySnapshot.isEmpty {
                        monitorService.scanSystemMemory()
                    }
                }
            )
            if isSystemSnapshotExpanded {
                SystemMemorySnapshotSection(
                    users: monitorService.systemMemorySnapshot,
                    isScanning: monitorService.isScanningSystemMemory,
                    onRefresh: { monitorService.scanSystemMemory() }
                )
            }
        }
    }
```

- [ ] **Step 5: Add the catalog entry**

Edit `ProcessMonitor/Resources/Localizable.xcstrings`. Find the `"strings"` object and add this entry (comma-separated with an existing neighboring entry — insertion position within the object doesn't matter, JSON key order isn't semantically significant to Xcode's string catalog tooling):

```json
    "Top Processes" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Top Processes" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Principais Processos" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Procesos Principales" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Processus Principaux" } },
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Top-Prozesse" } }
      }
    },
```

Validate the file is still well-formed JSON:

Run: `python3 -c "import json; json.load(open('ProcessMonitor/Resources/Localizable.xcstrings'))" && echo OK`
Expected: `OK`

- [ ] **Step 6: Build**

Run: `swift build`
Expected: `Build complete!` (no errors)

- [ ] **Step 7: Manual smoke test**

Run the app (see the project's `run` skill, or `swift run` / open the built app), click the menu bar icon to open the popover, then:
1. Click the chevron on the Memory row → it rotates 90°, a "Top Processes" section appears below with a spinner briefly, then up to 10 rows (name + memory, descending).
2. Click the refresh (⟳) icon → list re-populates.
3. Click the chevron again → section collapses; re-expanding does not show a spinner again (cached) unless refresh is tapped.

Confirm no visual glitching in both light and dark mode (menu bar icon → System Settings → Appearance, or `defaults write -g AppleInterfaceStyle Dark` and log out/in if a quick toggle isn't available).

- [ ] **Step 8: Commit**

```bash
rtk git add ProcessMonitor/Views/ProcessListView.swift ProcessMonitor/Resources/Localizable.xcstrings
rtk git commit -m "$(cat <<'EOF'
feat(monitor): show top system-wide RAM consumers in popover

Expandable "Top Processes" section under the RAM gauge, backed
by the on-demand scanSystemMemory() scan added in the previous
commit. Surfaces RAM hogs that were never added to the watch
list — the actual ask behind this feature.
EOF
)"
```

---

### Task 3: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Full build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 2: Full test suite**

Run: `swift test`
Expected: all tests pass, including the two new `ProcessMonitorServiceExtraTests` cases from Task 1.

- [ ] **Step 3: JVM/Gradle daemon check — not applicable**

This is a pure SwiftPM project; skip (no Gradle/JVM tooling involved).

- [ ] **Step 4: Confirm nothing else changed unexpectedly**

Run: `rtk git status`
Expected: only the files touched in Tasks 1-2 are modified/staged; nothing untracked left behind.
