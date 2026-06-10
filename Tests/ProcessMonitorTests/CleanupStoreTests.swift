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
        XCTAssertEqual(store.commands.count, 7)
        // Note: "iOS Simulator Data" seeds with isEnabled: false — don't assert allSatisfy(\.isEnabled)
    }

    func testDoesNotReseedWhenDataExists() {
        let defaults = Self.makeIsolatedDefaults()
        let store1 = CleanupStore(defaults: defaults)
        store1.add(CleanupCommand(id: UUID(), name: "Custom", command: "echo hi", isEnabled: true))
        let store2 = CleanupStore(defaults: defaults)
        XCTAssertEqual(store2.commands.count, 8)
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
}
