# Storage Cleaner Size Estimate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a pre-run "~X" size estimate pill on each Storage Cleaner command row, computed by running a read-only sibling of the command (a `du`/tool-check) instead of the real delete.

**Architecture:** A new pure-logic `CleanupSizeEstimator` turns a `CleanupCommand.command` string into a read-only shell "measurement command" (string transform only — no side effects, fully unit-testable without shelling out). `CleanupStore` gains a `sizeEstimates: [UUID: SizeEstimate]` published dictionary and a `refreshEstimates()` method that runs those measurement commands on a dedicated background queue, concurrently, separate from the existing sequential run-queue. `StorageCleanerView` calls `refreshEstimates()` on appear and `CleanupCommandRow` shows a gray "Calculating…" / "~X" pill until a real run supersedes it with the existing green "Freed X" pill.

**Tech Stack:** SwiftUI, Foundation (`Process`/`Pipe`, `NSRegularExpression`), XCTest. No new dependencies.

## Global Constraints

- Estimator commands must never modify the filesystem or any tool state — read-only only (`du`, `docker system df`, `brew --cache`, etc.), never the destructive verb itself.
- Estimator failures (missing tool, bad path, non-zero exit, unparsable output) must never surface as an error — they resolve to "no pill", same as a command with no applicable estimator.
- Estimating must never block or delay the Run / Run All buttons — separate queue from `performRun`.
- A real run's result (`runState` + `freedBytes`) always visually wins over a stale estimate for that row.
- Every measurement command's stdout, on success, is a single plain decimal integer (bytes) — no scientific notation, no unit suffix. Enforced via `awk 'printf "%d", ...'` rather than `awk '{print ...}'`.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `ProcessMonitor/Services/CleanupSizeEstimator.swift` | Pure string transform: command → read-only measurement command, or nil |
| Create | `Tests/ProcessMonitorTests/CleanupSizeEstimatorTests.swift` | Unit tests for the transform |
| Modify | `ProcessMonitor/Stores/CleanupStore.swift` | Add `SizeEstimate` enum, `sizeEstimates` state, `refreshEstimates()` |
| Modify | `Tests/ProcessMonitorTests/CleanupStoreTests.swift` | Tests for `refreshEstimates()` |
| Modify | `ProcessMonitor/Views/StorageCleanerView.swift` | Call `refreshEstimates()` on appear; row pill priority logic |

---

## Task 1: `CleanupSizeEstimator` (pure string transform)

**Files:**
- Create: `ProcessMonitor/Services/CleanupSizeEstimator.swift`
- Test: `Tests/ProcessMonitorTests/CleanupSizeEstimatorTests.swift`

**Interfaces:**
- Produces: `enum CleanupSizeEstimator { static func measurementCommand(for command: String) -> String? }` — later tasks (`CleanupStore`) call this directly.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ProcessMonitorTests/CleanupSizeEstimatorTests.swift`:

```swift
import XCTest
@testable import ProcessMonitor

final class CleanupSizeEstimatorTests: XCTestCase {

    // MARK: - Path-based

    func testSimpleRmRf() {
        let result = CleanupSizeEstimator.measurementCommand(for: "rm -rf ~/.gradle/caches")
        XCTAssertEqual(result, "du -sck ~/.gradle/caches 2>/dev/null | tail -1 | awk '{printf \"%d\", $1*1024}'")
    }

    func testRmF() {
        let result = CleanupSizeEstimator.measurementCommand(for: "rm -f ~/foo.log")
        XCTAssertEqual(result, "du -sck ~/foo.log 2>/dev/null | tail -1 | awk '{printf \"%d\", $1*1024}'")
    }

    func testMultiplePathsInSingleRmClause() {
        let command = #"rm -rf ~/Library/Application\ Support/Cursor/Cache ~/Library/Application\ Support/Cursor/GPUCache"#
        let expected = #"du -sck ~/Library/Application\ Support/Cursor/Cache ~/Library/Application\ Support/Cursor/GPUCache 2>/dev/null | tail -1 | awk '{printf "%d", $1*1024}'"#
        XCTAssertEqual(CleanupSizeEstimator.measurementCommand(for: command), expected)
    }

    func testFindDeletePlusRmClause() {
        let command = #"find ~/Library/Application\ Support/Cursor/User/workspaceStorage -name "state.vscdb*" -delete; rm -f ~/Library/Application\ Support/Cursor/User/globalStorage/state.vscdb*"#
        let expected = #"du -sck ~/Library/Application\ Support/Cursor/User/workspaceStorage ~/Library/Application\ Support/Cursor/User/globalStorage/state.vscdb* 2>/dev/null | tail -1 | awk '{printf "%d", $1*1024}'"#
        XCTAssertEqual(CleanupSizeEstimator.measurementCommand(for: command), expected)
    }

    func testGlobPathPreserved() {
        let result = CleanupSizeEstimator.measurementCommand(for: "rm -rf ~/Library/Developer/Xcode/DerivedData/*")
        XCTAssertEqual(result, "du -sck ~/Library/Developer/Xcode/DerivedData/* 2>/dev/null | tail -1 | awk '{printf \"%d\", $1*1024}'")
    }

    // MARK: - Known-tool heuristics

    func testBrewCleanup() {
        let result = CleanupSizeEstimator.measurementCommand(for: "brew cleanup --prune=all")
        XCTAssertEqual(result, #"command -v brew >/dev/null 2>&1 && du -sk "$(brew --cache)" 2>/dev/null | awk '{printf "%d", $1*1024}'"#)
    }

    func testNpmCacheClean() {
        let result = CleanupSizeEstimator.measurementCommand(for: "npm cache clean --force")
        XCTAssertEqual(result, #"command -v npm >/dev/null 2>&1 && du -sk "$(npm config get cache 2>/dev/null)" 2>/dev/null | awk '{printf "%d", $1*1024}'"#)
    }

    func testPodCacheClean() {
        let result = CleanupSizeEstimator.measurementCommand(for: "pod cache clean --all")
        XCTAssertEqual(result, #"command -v pod >/dev/null 2>&1 && du -sk ~/Library/Caches/CocoaPods 2>/dev/null | awk '{printf "%d", $1*1024}'"#)
    }

    func testDockerSystemPrune() {
        let result = CleanupSizeEstimator.measurementCommand(for: "docker system prune --volumes -f")
        XCTAssertEqual(result, #"command -v docker >/dev/null 2>&1 && docker system df --format '{{.Reclaimable}}' 2>/dev/null | sed -E 's/ *\([0-9]+%\)//' | awk '/TB$/{gsub(/TB$/,"");sum+=$1*1099511627776} /GB$/{gsub(/GB$/,"");sum+=$1*1073741824} /MB$/{gsub(/MB$/,"");sum+=$1*1048576} /kB$/{gsub(/kB$/,"");sum+=$1*1024} /B$/{gsub(/B$/,"");sum+=$1} END{printf "%d", sum}'"#)
    }

    func testSimctlDeleteUnavailable() {
        let result = CleanupSizeEstimator.measurementCommand(for: "xcrun simctl delete unavailable")
        XCTAssertEqual(result, #"xcrun simctl list devices unavailable 2>/dev/null | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' | while read -r id; do du -sk "$HOME/Library/Developer/CoreSimulator/Devices/$id" 2>/dev/null; done | awk '{sum+=$1} END{printf "%d", sum*1024}'"#)
    }

    func testSimctlEraseAll() {
        let result = CleanupSizeEstimator.measurementCommand(for: "xcrun simctl shutdown all 2>/dev/null; xcrun simctl erase all")
        XCTAssertEqual(result, #"xcrun simctl list devices 2>/dev/null | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' | while read -r id; do du -sk "$HOME/Library/Developer/CoreSimulator/Devices/$id" 2>/dev/null; done | awk '{sum+=$1} END{printf "%d", sum*1024}'"#)
    }

    // MARK: - No estimator applies

    func testPlainCommandHasNoEstimator() {
        XCTAssertNil(CleanupSizeEstimator.measurementCommand(for: "echo hello"))
    }

    func testScanCommandHasNoEstimator() {
        let scan = #"find ~ -path "$HOME/Library" -prune -o -type d \( -name build -o -name DerivedData \) -prune -exec du -sh {} + 2>/dev/null | sort -rh | head -30"#
        // Contains "find" but with no "-delete" flag — must not match the find-path heuristic.
        XCTAssertNil(CleanupSizeEstimator.measurementCommand(for: scan))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail (type doesn't exist yet)**

Run: `swift test --filter CleanupSizeEstimatorTests 2>&1 | tail -30`
Expected: FAIL — `error: cannot find 'CleanupSizeEstimator' in scope`

- [ ] **Step 3: Implement `CleanupSizeEstimator`**

Create `ProcessMonitor/Services/CleanupSizeEstimator.swift`:

```swift
import Foundation

/// Turns a `CleanupCommand.command` string into a read-only shell command that
/// estimates (in bytes) how much disk space the real command would free, without
/// deleting anything. Returns nil when no heuristic applies — callers must treat
/// that as "no estimate available", not an error.
enum CleanupSizeEstimator {

    static func measurementCommand(for command: String) -> String? {
        if let pathCommand = pathBasedMeasurementCommand(for: command) {
            return pathCommand
        }
        return knownToolMeasurementCommand(for: command)
    }

    // MARK: - Path-based (rm -rf / rm -f / find ... -delete)

    /// Captures everything after `rm -rf`/`rm -f` up to the next `;`/`&&`/`||` or
    /// end of string — may itself contain several space-separated paths (e.g. the
    /// Cursor Cache command lists six), which is fine: `du` accepts multiple operands.
    private static let rmClauseRegex = try! NSRegularExpression(
        pattern: #"rm\s+-[a-zA-Z]*f[a-zA-Z]*\s+([^;&|]+)"#,
        options: [.caseInsensitive]
    )
    /// Captures only the single path argument immediately after `find`, respecting
    /// backslash-escaped spaces (`\ `) so it doesn't stop mid-path.
    private static let findPathRegex = try! NSRegularExpression(
        pattern: #"\bfind\s+((?:\\ |\S)+)"#,
        options: [.caseInsensitive]
    )

    private static func pathBasedMeasurementCommand(for command: String) -> String? {
        // "find" without "-delete" is a read-only scan (e.g. the built-in "Scan:"
        // commands) — nothing will actually be freed, so it gets no estimate.
        let hasFindDelete = command.range(of: #"\bfind\b.*-delete"#, options: [.regularExpression, .caseInsensitive]) != nil
        let hasRm = command.range(of: #"\brm\s+-[a-zA-Z]*f"#, options: [.regularExpression, .caseInsensitive]) != nil
        guard hasFindDelete || hasRm else { return nil }

        let ns = command as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var targets: [String] = []

        for match in rmClauseRegex.matches(in: command, range: fullRange) {
            guard match.numberOfRanges > 1 else { continue }
            let captured = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if !captured.isEmpty { targets.append(captured) }
        }
        if hasFindDelete {
            for match in findPathRegex.matches(in: command, range: fullRange) {
                guard match.numberOfRanges > 1 else { continue }
                let captured = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if !captured.isEmpty { targets.append(captured) }
            }
        }

        guard !targets.isEmpty else { return nil }
        return "du -sck \(targets.joined(separator: " ")) 2>/dev/null | tail -1 | awk '{printf \"%d\", $1*1024}'"
    }

    // MARK: - Known-tool heuristics (fixed table, matches seeded non-path commands)

    private static func knownToolMeasurementCommand(for command: String) -> String? {
        let lower = command.lowercased()
        return knownTools.first { lower.contains($0.match) }?.command
    }

    private static let knownTools: [(match: String, command: String)] = [
        ("xcrun simctl delete unavailable", simctlUnavailableCommand),
        ("xcrun simctl erase all", simctlEraseAllCommand),
        ("brew cleanup", #"command -v brew >/dev/null 2>&1 && du -sk "$(brew --cache)" 2>/dev/null | awk '{printf "%d", $1*1024}'"#),
        ("npm cache clean", #"command -v npm >/dev/null 2>&1 && du -sk "$(npm config get cache 2>/dev/null)" 2>/dev/null | awk '{printf "%d", $1*1024}'"#),
        ("pod cache clean", #"command -v pod >/dev/null 2>&1 && du -sk ~/Library/Caches/CocoaPods 2>/dev/null | awk '{printf "%d", $1*1024}'"#),
        ("docker system prune", dockerReclaimableCommand),
    ]

    /// Lists unavailable-runtime device UDIDs as plain text (no `jq`/JSON parsing
    /// needed) and sums each device directory's size.
    private static let simctlUnavailableCommand = #"xcrun simctl list devices unavailable 2>/dev/null | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' | while read -r id; do du -sk "$HOME/Library/Developer/CoreSimulator/Devices/$id" 2>/dev/null; done | awk '{sum+=$1} END{printf "%d", sum*1024}'"#

    /// Same approach as above but over every device (approximates "erase all" —
    /// each device folder's full size, not just its resettable Data subfolder).
    private static let simctlEraseAllCommand = #"xcrun simctl list devices 2>/dev/null | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' | while read -r id; do du -sk "$HOME/Library/Developer/CoreSimulator/Devices/$id" 2>/dev/null; done | awk '{sum+=$1} END{printf "%d", sum*1024}'"#

    /// `docker system df --format '{{.Reclaimable}}'` prints one human-readable size
    /// per row (e.g. "1.24GB (76%)") — strip the percentage, convert each unit
    /// suffix to bytes, and sum.
    private static let dockerReclaimableCommand = #"command -v docker >/dev/null 2>&1 && docker system df --format '{{.Reclaimable}}' 2>/dev/null | sed -E 's/ *\([0-9]+%\)//' | awk '/TB$/{gsub(/TB$/,"");sum+=$1*1099511627776} /GB$/{gsub(/GB$/,"");sum+=$1*1073741824} /MB$/{gsub(/MB$/,"");sum+=$1*1048576} /kB$/{gsub(/kB$/,"");sum+=$1*1024} /B$/{gsub(/B$/,"");sum+=$1} END{printf "%d", sum}'"#
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CleanupSizeEstimatorTests 2>&1 | tail -30`
Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
rtk git add ProcessMonitor/Services/CleanupSizeEstimator.swift Tests/ProcessMonitorTests/CleanupSizeEstimatorTests.swift
rtk git commit -m "$(cat <<'EOF'
feat(storage): add read-only size estimator for cleanup commands

Pure string transform: turns a cleanup command's rm/find target paths
(or a fixed known-tool table for brew/npm/docker/pod/simctl) into a
read-only du-based measurement command. No filesystem side effects.
EOF
)"
```

---

## Task 2: `CleanupStore` — `SizeEstimate` state + `refreshEstimates()`

**Files:**
- Modify: `ProcessMonitor/Stores/CleanupStore.swift`
- Test: `Tests/ProcessMonitorTests/CleanupStoreTests.swift`

**Interfaces:**
- Consumes: `CleanupSizeEstimator.measurementCommand(for:) -> String?` (Task 1)
- Produces: `enum SizeEstimate: Equatable { case pending; case computed(Int64) }`, `CleanupStore.sizeEstimate(for id: UUID) -> SizeEstimate?`, `CleanupStore.refreshEstimates()` — consumed by `StorageCleanerView` (Task 3)

- [ ] **Step 1: Write the failing tests**

Add to `Tests/ProcessMonitorTests/CleanupStoreTests.swift` (append before the final closing brace, after the existing `// MARK: - Execution` section):

```swift
    // MARK: - Size estimates

    @discardableResult
    private func waitForEstimate(_ store: CleanupStore, _ id: UUID, timeout: TimeInterval = 5) -> SizeEstimate? {
        let exp = expectation(description: "estimate computed")
        var result: SizeEstimate?
        func poll() {
            if case .computed = store.sizeEstimate(for: id) {
                result = store.sizeEstimate(for: id)
                exp.fulfill()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
            }
        }
        poll()
        wait(for: [exp], timeout: timeout)
        return result
    }

    func testRefreshEstimatesComputesSizeForPathBasedCommand() {
        let store = makeStore()
        for c in store.commands { store.remove(id: c.id) }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("pm-estimate-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let file = tempDir.appendingPathComponent("data.bin")
        try? Data(repeating: 0, count: 8192).write(to: file)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cmd = CleanupCommand(id: UUID(), name: "Test Cleanup", command: "rm -rf \(tempDir.path)", isEnabled: true)
        store.add(cmd)

        store.refreshEstimates()
        XCTAssertEqual(store.sizeEstimate(for: cmd.id), .pending)

        guard case let .computed(bytes) = waitForEstimate(store, cmd.id) else {
            return XCTFail("expected a computed estimate")
        }
        XCTAssertGreaterThan(bytes, 0)
    }

    func testRefreshEstimatesSkipsCommandWithNoEstimator() {
        let store = makeStore()
        for c in store.commands { store.remove(id: c.id) }
        let cmd = CleanupCommand(id: UUID(), name: "Echo", command: "echo hi", isEnabled: true)
        store.add(cmd)

        store.refreshEstimates()

        let exp = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertNil(store.sizeEstimate(for: cmd.id))
    }

    func testRefreshEstimatesSkipsDisabledCommands() {
        let store = makeStore()
        for c in store.commands { store.remove(id: c.id) }
        let cmd = CleanupCommand(id: UUID(), name: "Disabled Cleanup", command: "rm -rf /tmp/pm-estimate-disabled-test", isEnabled: false)
        store.add(cmd)

        store.refreshEstimates()

        let exp = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertNil(store.sizeEstimate(for: cmd.id))
    }
```

- [ ] **Step 2: Run tests to verify they fail (API doesn't exist yet)**

Run: `swift test --filter CleanupStoreTests 2>&1 | tail -30`
Expected: FAIL — `error: value of type 'CleanupStore' has no member 'sizeEstimate'` (and `refreshEstimates`)

- [ ] **Step 3: Implement `SizeEstimate` + `refreshEstimates()`**

In `ProcessMonitor/Stores/CleanupStore.swift`, add this enum right after the existing `RunState` enum (after line 9, before `final class CleanupStore`):

```swift
/// A cleanup command's pre-run estimated freed size. `.pending` while the
/// measurement is running; the key is absent from the store's dictionary
/// entirely when no estimator applies to that command (permanent — never
/// becomes `.pending` or `.computed`).
enum SizeEstimate: Equatable {
    case pending
    case computed(Int64)
}
```

Then, inside `final class CleanupStore`, add these two published/private properties right after the existing `freedBytes` property (after line 16):

```swift
    /// Pre-run size estimates, keyed by command id. Absent key = no estimator
    /// applies to that command. Recomputed from scratch each time
    /// `refreshEstimates()` is called (e.g. every time the Storage tab appears).
    @Published private(set) var sizeEstimates: [UUID: SizeEstimate] = [:]
    private var isEstimating = false
    private let estimateQueue = DispatchQueue(label: "CleanupStore.estimate", qos: .utility, attributes: .concurrent)
```

Then, inside the `// MARK: - Accessors` section, add right after the existing `runState(for:)` method:

```swift
    func sizeEstimate(for id: UUID) -> SizeEstimate? {
        sizeEstimates[id]
    }
```

Then, add a new method — put it right after `runAll()`, before the `// MARK: - Private` marker:

```swift
    /// Recomputes size estimates for every enabled command that has an applicable
    /// estimator. Safe to call repeatedly (e.g. on every view appear) — a call
    /// while a previous pass is still in flight is a no-op, so scans never stack.
    /// Runs concurrently on a dedicated queue, separate from the cleanup-run queue,
    /// so estimating never delays Run / Run All.
    func refreshEstimates() {
        guard !isEstimating else { return }
        let targets = commands.filter { $0.isEnabled && CleanupSizeEstimator.measurementCommand(for: $0.command) != nil }
        guard !targets.isEmpty else { return }

        isEstimating = true
        for cmd in targets { sizeEstimates[cmd.id] = .pending }

        let group = DispatchGroup()
        for cmd in targets {
            guard let measurementCommand = CleanupSizeEstimator.measurementCommand(for: cmd.command) else { continue }
            group.enter()
            estimateQueue.async { [weak self] in
                let bytes = self?.runEstimate(measurementCommand)
                DispatchQueue.main.async {
                    if let bytes {
                        self?.sizeEstimates[cmd.id] = .computed(bytes)
                    } else {
                        self?.sizeEstimates.removeValue(forKey: cmd.id)
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in self?.isEstimating = false }
    }
```

Then, add this private helper inside the `// MARK: - Private` section, right after `performRun`:

```swift
    /// Runs a read-only measurement command and parses its stdout as a byte count.
    /// Returns nil on any failure (tool missing, non-zero exit, unparsable output) —
    /// callers treat that as "no estimate available", never as an error.
    private func runEstimate(_ measurementCommand: String) -> Int64? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "unsetopt nomatch; " + measurementCommand]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Int64(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CleanupStoreTests 2>&1 | tail -30`
Expected: all tests PASS (including the pre-existing ones — no regressions)

- [ ] **Step 5: Commit**

```bash
rtk git add ProcessMonitor/Stores/CleanupStore.swift Tests/ProcessMonitorTests/CleanupStoreTests.swift
rtk git commit -m "$(cat <<'EOF'
feat(storage): compute pre-run size estimates in CleanupStore

refreshEstimates() runs each enabled command's read-only measurement
command concurrently on a dedicated queue, publishing .pending then
.computed(bytes) per command id. Never blocks the existing run queue.
EOF
)"
```

---

## Task 3: `StorageCleanerView` — wire estimates into the UI

**Files:**
- Modify: `ProcessMonitor/Views/StorageCleanerView.swift`

**Interfaces:**
- Consumes: `CleanupStore.refreshEstimates()`, `CleanupStore.sizeEstimate(for:) -> SizeEstimate?`, `SizeEstimate` (Task 2)

- [ ] **Step 1: Trigger estimation on appear**

In `ProcessMonitor/Views/StorageCleanerView.swift`, modify the existing `.onAppear` modifier on `StorageCleanerView.body` (currently at line 63):

Before:
```swift
        .onAppear { fullDiskAccessGranted = FullDiskAccessService.isGranted }
```

After:
```swift
        .onAppear {
            fullDiskAccessGranted = FullDiskAccessService.isGranted
            store.refreshEstimates()
        }
```

- [ ] **Step 2: Pass the estimate into each row**

In the same file, modify the `ForEach` inside `body` (currently at lines 29-43) to pass the new value:

Before:
```swift
                    ForEach(store.commands) { cmd in
                        CleanupCommandRow(
                            command: cmd,
                            runState: store.runState(for: cmd.id),
                            freedBytes: store.freedBytes[cmd.id],
                            anyRunning: store.isAnyRunning,
                            onToggle: {
```

After:
```swift
                    ForEach(store.commands) { cmd in
                        CleanupCommandRow(
                            command: cmd,
                            runState: store.runState(for: cmd.id),
                            freedBytes: store.freedBytes[cmd.id],
                            sizeEstimate: store.sizeEstimate(for: cmd.id),
                            anyRunning: store.isAnyRunning,
                            onToggle: {
```

- [ ] **Step 3: Accept the new parameter and add the pill views**

In the same file, modify `CleanupCommandRow` (currently starting at line 191):

Before:
```swift
private struct CleanupCommandRow: View {
    let command: CleanupCommand
    let runState: RunState
    let freedBytes: Int64?
    let anyRunning: Bool
```

After:
```swift
private struct CleanupCommandRow: View {
    let command: CleanupCommand
    let runState: RunState
    let freedBytes: Int64?
    let sizeEstimate: SizeEstimate?
    let anyRunning: Bool
```

Then, in the same struct's `body`, replace the existing pill conditional (currently lines 224-226):

Before:
```swift
                if case .success = runState, let freedBytes {
                    freedPill(freedBytes)
                }
```

After:
```swift
                statusPill
```

Then add this computed property and the two new pill views right after the existing `freedPill(_:)` method (currently ends at line 344, right before `@ViewBuilder private var statusBadge`):

```swift
    /// A run's confirmed result always wins over a stale estimate for that row.
    @ViewBuilder
    private var statusPill: some View {
        if case .success = runState, let freedBytes {
            freedPill(freedBytes)
        } else if let sizeEstimate {
            switch sizeEstimate {
            case .pending:
                calculatingPill
            case .computed(let bytes):
                estimatePill(bytes)
            }
        }
    }

    private var calculatingPill: some View {
        Text(NSLocalizedString("Calculating…", comment: "Placeholder shown while a cleanup command's estimated freed space is being computed"))
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.14)))
            .fixedSize()
    }

    /// Gray "~X" pill — deliberately not green like `freedPill`, so an estimate is
    /// never mistaken for a confirmed result.
    private func estimatePill(_ bytes: Int64) -> some View {
        Text(String(
            format: NSLocalizedString("~%@", comment: "Estimated disk space a cleanup command would free, shown before it has been run"),
            ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        ))
        .font(.system(.caption2, design: .rounded, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.14)))
        .fixedSize()
    }
```

- [ ] **Step 4: Build and run the app manually**

Run: `swift build 2>&1 | tail -30`
Expected: build succeeds with no errors.

Then launch the app, open Settings → Storage, and verify:
- Path-based commands (Xcode DerivedData, Gradle Caches, Android Studio, Claude VM Bundles, Cursor Cache) show "Calculating…" briefly, then a gray "~X" pill.
- Known-tool commands (Homebrew, npm cache, Docker, CocoaPods, both `xcrun simctl` entries) show a pill too (assuming those tools are installed).
- The two `Scan:` commands and any disabled command show no pill.
- Running a command switches its pill from gray "~X" to green "Freed X" and it stays that way.
- Switching to another settings tab and back to Storage re-triggers "Calculating…" and refreshes the pills.

- [ ] **Step 5: Run the full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: all tests PASS, no regressions.

- [ ] **Step 6: Commit**

```bash
rtk git add ProcessMonitor/Views/StorageCleanerView.swift
rtk git commit -m "$(cat <<'EOF'
feat(storage): show pre-run size estimate pill on cleanup rows

Storage tab now computes a "~X" estimate per command on appear,
via CleanupStore.refreshEstimates(). A confirmed run result still
takes priority over the estimate for that row.
EOF
)"
```

---

## Self-Review Notes

- **Spec coverage:** path-based extraction (Task 1), known-tool table (Task 1), pending/computed/absent state semantics (Task 2), separate queue from run queue (Task 2), on-appear live refresh with re-entrancy guard (Task 2/3), pill priority + "Calculating…" placeholder (Task 3), silent failure handling (Task 1 nil / Task 2 `runEstimate` nil path) — all covered.
- **Out of scope items honored:** no UI for editing the known-tool table, no estimate caching across launches, no per-path progress breakdown.
