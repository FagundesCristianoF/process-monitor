import XCTest
@testable import ProcessMonitor

final class CleanupStoreTests: XCTestCase {

    private func makeStore(defaults: UserDefaults = makeIsolatedDefaults()) -> CleanupStore {
        CleanupStore(defaults: defaults)
    }

    private static func makeIsolatedDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    // MARK: - Seeding

    func testSeedsDefaultCommandsOnFirstLoad() {
        let store = makeStore()
        XCTAssertEqual(store.commands.count, 15)
        // Note: several seeds (e.g. "iOS Simulator Data", scans) seed with isEnabled: false —
        // don't assert allSatisfy(\.isEnabled)
    }

    func testDoesNotReseedWhenDataExists() {
        let defaults = Self.makeIsolatedDefaults()
        let store1 = CleanupStore(defaults: defaults)
        store1.add(CleanupCommand(id: UUID(), name: "Custom", command: "echo hi", isEnabled: true))
        let store2 = CleanupStore(defaults: defaults)
        XCTAssertEqual(store2.commands.count, 16)
    }

    // MARK: - Seed merge migration

    func testMergeAppendsNewSeedsForPreMigrationData() {
        // Simulate a pre-migration install: persisted commands but no seeded-names record.
        let defaults = Self.makeIsolatedDefaults()
        let legacy = [CleanupCommand(id: UUID(), name: "Homebrew", command: "brew cleanup --prune=all", isEnabled: true)]
        defaults.set(try? JSONEncoder().encode(legacy), forKey: "cleanupCommands")

        let store = CleanupStore(defaults: defaults)
        // Existing command preserved.
        XCTAssertTrue(store.commands.contains { $0.name == "Homebrew" })
        // Newer default introduced after their data was written gets appended.
        XCTAssertTrue(store.commands.contains { $0.name == "Gradle Caches" })
        // No duplicate of the command they already had.
        XCTAssertEqual(store.commands.filter { $0.name == "Homebrew" }.count, 1)
    }

    func testRepairsLegacySimctlEraseCommand() {
        // A pre-fix install persisted the bug-prone "erase all" (fails on a booted sim).
        let defaults = Self.makeIsolatedDefaults()
        let legacy = [CleanupCommand(id: UUID(), name: "iOS Simulator Data", command: "xcrun simctl erase all", isEnabled: false)]
        defaults.set(try? JSONEncoder().encode(legacy), forKey: "cleanupCommands")

        let store = CleanupStore(defaults: defaults)
        let cmd = store.commands.first { $0.name == "iOS Simulator Data" }
        XCTAssertEqual(cmd?.command, "xcrun simctl shutdown all 2>/dev/null; xcrun simctl erase all")
    }

    func testDoesNotTouchCustomizedSimctlCommand() {
        // If the user edited the command, the repair must leave it alone.
        let defaults = Self.makeIsolatedDefaults()
        let custom = [CleanupCommand(id: UUID(), name: "iOS Simulator Data", command: "xcrun simctl erase MyDevice", isEnabled: false)]
        defaults.set(try? JSONEncoder().encode(custom), forKey: "cleanupCommands")

        let store = CleanupStore(defaults: defaults)
        let cmd = store.commands.first { $0.name == "iOS Simulator Data" }
        XCTAssertEqual(cmd?.command, "xcrun simctl erase MyDevice")
    }

    func testMergeDoesNotResurrectDeletedSeed() {
        let defaults = Self.makeIsolatedDefaults()
        let store1 = CleanupStore(defaults: defaults)          // seeds + records seeded names
        let gradle = store1.commands.first { $0.name == "Gradle Caches" }!
        store1.remove(id: gradle.id)

        let store2 = CleanupStore(defaults: defaults)
        XCTAssertFalse(store2.commands.contains { $0.name == "Gradle Caches" })
    }

    // MARK: - CRUD

    func testAddCommand() {
        let store = makeStore()
        let cmd = CleanupCommand(id: UUID(), name: "Test", command: "echo hi", isEnabled: true)
        store.add(cmd)
        XCTAssertTrue(store.commands.contains(where: { $0.id == cmd.id }))
    }

    func testUpdateCommand() {
        let store = makeStore()
        var cmd = store.commands[0]
        cmd.name = "Renamed"
        store.update(cmd)
        XCTAssertEqual(store.commands.first(where: { $0.id == cmd.id })?.name, "Renamed")
    }

    func testRemoveCommand() {
        let store = makeStore()
        let id = store.commands[0].id
        store.remove(id: id)
        XCTAssertFalse(store.commands.contains(where: { $0.id == id }))
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() {
        let defaults = Self.makeIsolatedDefaults()
        let store1 = CleanupStore(defaults: defaults)
        let cmd = CleanupCommand(id: UUID(), name: "Persisted", command: "echo ok", isEnabled: false)
        store1.add(cmd)

        let store2 = CleanupStore(defaults: defaults)
        XCTAssertTrue(store2.commands.contains(where: { $0.id == cmd.id && $0.name == "Persisted" }))
    }

    // MARK: - RunState

    func testRunStateDefaultsToIdle() {
        let store = makeStore()
        let id = store.commands[0].id
        XCTAssertEqual(store.runState(for: id), .idle)
    }

    // MARK: - executableName

    func testExecutableNameSimpleCommand() {
        XCTAssertEqual(CleanupStore.executableName(from: "npm cache clean --force"), "npm")
    }

    func testExecutableNameMultiTokenTool() {
        XCTAssertEqual(CleanupStore.executableName(from: "xcrun simctl erase all"), "xcrun")
    }

    func testExecutableNameAbsolutePath() {
        XCTAssertEqual(CleanupStore.executableName(from: "/opt/homebrew/bin/brew cleanup"), "/opt/homebrew/bin/brew")
    }

    func testExecutableNameSkipsEnvAssignments() {
        XCTAssertEqual(CleanupStore.executableName(from: "FOO=bar BAZ=1 npm run x"), "npm")
    }

    func testExecutableNameEmptyCommand() {
        XCTAssertNil(CleanupStore.executableName(from: "   "))
    }

    // MARK: - Execution

    @discardableResult
    private func waitForTerminalState(_ store: CleanupStore, _ id: UUID, timeout: TimeInterval = 5) -> RunState {
        let exp = expectation(description: "terminal state")
        var result: RunState = .idle
        func poll() {
            switch store.runState(for: id) {
            case .success, .failure:
                result = store.runState(for: id)
                exp.fulfill()
            default:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
            }
        }
        poll()
        wait(for: [exp], timeout: timeout)
        return result
    }

    func testRunSuccessCapturesStdout() {
        let store = makeStore()
        let cmd = CleanupCommand(id: UUID(), name: "Echo", command: "echo hello-world", isEnabled: true)
        store.add(cmd)
        store.run(id: cmd.id)
        guard case let .success(output) = waitForTerminalState(store, cmd.id) else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(output.contains("hello-world"))
    }

    func testRunMissingCommandReturnsPathHint() {
        let store = makeStore()
        let missing = "pmnosuchcmd_\(UUID().uuidString.prefix(8))"
        let cmd = CleanupCommand(id: UUID(), name: "Missing", command: "\(missing) cleanup", isEnabled: true)
        store.add(cmd)
        store.run(id: cmd.id)
        guard case let .failure(output) = waitForTerminalState(store, cmd.id) else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(output.contains("not found"))
        XCTAssertTrue(output.contains("PATH"))
        XCTAssertTrue(output.contains(missing))
    }

    func testRunDisabledCommandStaysIdle() {
        let store = makeStore()
        let cmd = CleanupCommand(id: UUID(), name: "Off", command: "echo nope", isEnabled: false)
        store.add(cmd)
        store.run(id: cmd.id)
        let exp = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(store.runState(for: cmd.id), .idle)
    }

    func testRunAllRunsEnabledCommands() {
        let store = makeStore()
        // Replace seeds with two known-good echo commands.
        for c in store.commands { store.remove(id: c.id) }
        let a = CleanupCommand(id: UUID(), name: "A", command: "echo a", isEnabled: true)
        let b = CleanupCommand(id: UUID(), name: "B", command: "echo b", isEnabled: true)
        store.add(a)
        store.add(b)
        store.runAll()
        waitForTerminalState(store, a.id)
        waitForTerminalState(store, b.id)
        if case .success = store.runState(for: a.id) {} else { XCTFail("A should succeed") }
        if case .success = store.runState(for: b.id) {} else { XCTFail("B should succeed") }
    }

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
}
