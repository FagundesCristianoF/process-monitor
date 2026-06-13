import XCTest
@testable import ProcessMonitor

final class ProcessConfigStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PMConfigTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore() -> ProcessConfigStore {
        let url = tempDir.appendingPathComponent("config.json")
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return ProcessConfigStore(configFileURL: url, defaults: defaults)
    }

    // MARK: - Seeding

    func testFreshStoreSeedsBuiltIns() {
        let store = makeStore()
        XCTAssertEqual(store.definitions.map(\.id).sorted(), ProcessDefinition.builtInDefaults.map(\.id).sorted())
        XCTAssertEqual(store.diskVolumes.map(\.id), ["root"])
        for def in store.definitions {
            XCTAssertNotNil(store.limits[def.id], "limit seeded for \(def.id)")
        }
    }

    func testPersistWritesFile() {
        _ = makeStore()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("config.json").path))
    }

    // MARK: - Limits

    func testLimitDefaultForUnknownID() {
        XCTAssertEqual(makeStore().limit(for: "nope"), 4096)
    }

    func testSetLimit() {
        let store = makeStore()
        store.setLimit(2048, for: "java")
        XCTAssertEqual(store.limit(for: "java"), 2048)
    }

    // MARK: - Auto-restart limits

    func testAutoRestartLimitNilWhenUnset() {
        XCTAssertNil(makeStore().autoRestartLimit(for: "java"))
    }

    func testSetAndClearAutoRestartLimit() {
        let store = makeStore()
        store.setAutoRestartLimit(8192, for: "java")
        XCTAssertEqual(store.autoRestartLimit(for: "java"), 8192)
        store.setAutoRestartLimit(nil, for: "java")
        XCTAssertNil(store.autoRestartLimit(for: "java"))
        store.setAutoRestartLimit(0, for: "java")
        XCTAssertNil(store.autoRestartLimit(for: "java"), "0 disables")
    }

    // MARK: - Definitions CRUD

    func testAddDefinitionDeduped() {
        let store = makeStore()
        let count = store.definitions.count
        let new = ProcessDefinition(id: "custom", displayName: "Custom", patterns: ["custom"], defaultLimitMB: 512)
        store.addDefinition(new)
        XCTAssertEqual(store.definitions.count, count + 1)
        XCTAssertEqual(store.limits["custom"], 512)
        store.addDefinition(new) // duplicate id ignored
        XCTAssertEqual(store.definitions.count, count + 1)
    }

    func testRemoveDefinition() {
        let store = makeStore()
        store.removeDefinition(id: "java")
        XCTAssertFalse(store.definitions.contains { $0.id == "java" })
        XCTAssertNil(store.limits["java"])
    }

    func testUpdateDefinition() {
        let store = makeStore()
        var d = store.definitions.first { $0.id == "java" }!
        d.displayName = "OpenJDK"
        store.updateDefinition(d)
        XCTAssertEqual(store.definitions.first { $0.id == "java" }?.displayName, "OpenJDK")
    }

    func testResetToDefaults() {
        let store = makeStore()
        store.removeDefinition(id: "java")
        store.resetToDefaults()
        XCTAssertEqual(store.definitions.map(\.id).sorted(), ProcessDefinition.builtInDefaults.map(\.id).sorted())
    }

    // MARK: - Disk volumes CRUD

    func testDiskVolumeCRUD() {
        let store = makeStore()
        let vol = DiskVolume(id: "ext", displayName: "External", path: "/Volumes/Ext", thresholdPercent: 5, thresholdGB: nil)
        store.addDiskVolume(vol)
        XCTAssertTrue(store.diskVolumes.contains { $0.id == "ext" })
        store.addDiskVolume(vol) // dedup
        XCTAssertEqual(store.diskVolumes.filter { $0.id == "ext" }.count, 1)

        var updated = vol
        updated.displayName = "Backup"
        store.updateDiskVolume(updated)
        XCTAssertEqual(store.diskVolumes.first { $0.id == "ext" }?.displayName, "Backup")

        store.removeDiskVolume(id: "ext")
        XCTAssertFalse(store.diskVolumes.contains { $0.id == "ext" })
    }

    // MARK: - Poll interval clamping

    func testPollIntervalClampsLow() {
        let store = makeStore()
        store.pollIntervalSeconds = 0.1
        XCTAssertEqual(store.pollIntervalSeconds, ProcessConfigStore.minPollInterval)
    }

    func testPollIntervalClampsHigh() {
        let store = makeStore()
        store.pollIntervalSeconds = 999
        XCTAssertEqual(store.pollIntervalSeconds, ProcessConfigStore.maxPollInterval)
    }

    func testIsPausedTogglePersists() {
        let store = makeStore()
        store.isPaused = true
        XCTAssertTrue(store.isPaused)
    }

    // MARK: - Persistence round trip

    func testRoundTripAcrossStores() {
        let url = tempDir.appendingPathComponent("config.json")
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let s1 = ProcessConfigStore(configFileURL: url, defaults: defaults)
        s1.setLimit(1234, for: "java")
        s1.setAutoRestartLimit(5678, for: "java")
        s1.pollIntervalSeconds = 12

        let s2 = ProcessConfigStore(configFileURL: url, defaults: defaults)
        XCTAssertEqual(s2.limit(for: "java"), 1234)
        XCTAssertEqual(s2.autoRestartLimit(for: "java"), 5678)
        XCTAssertEqual(s2.pollIntervalSeconds, 12)
    }

    // MARK: - Migration

    func testMigrationUpdatesStalePatternsAndAddsMissingBuiltIns() throws {
        let url = tempDir.appendingPathComponent("config.json")
        let legacy = """
        {
          "definitions": [
            {"id": "java", "displayName": "Java", "patterns": ["stale-pattern"], "defaultLimitMB": 4096}
          ],
          "limits": {"java": 4096},
          "pollIntervalSeconds": 5,
          "isPaused": false,
          "patternSchemaVersion": 0
        }
        """
        try legacy.data(using: .utf8)!.write(to: url)

        let store = ProcessConfigStore(configFileURL: url, defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        let java = store.definitions.first { $0.id == "java" }
        XCTAssertEqual(java?.patterns, ["java"], "stale patterns migrated to built-in")
        XCTAssertTrue(store.definitions.contains { $0.id == "xcode" }, "missing built-ins appended")
    }
}
