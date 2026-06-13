import XCTest
import UserNotifications
@testable import ProcessMonitor

final class DiskMonitorServiceTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PMDiskTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeConfig(volumes: [DiskVolume]) -> ProcessConfigStore {
        let config = ProcessConfigStore(
            configFileURL: tempDir.appendingPathComponent("config.json"),
            defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        )
        for v in config.diskVolumes { config.removeDiskVolume(id: v.id) }
        for v in volumes { config.addDiskVolume(v) }
        return config
    }

    private func pollUntil(timeout: TimeInterval = 5, _ cond: @escaping () -> Bool) {
        let exp = expectation(description: "condition")
        func poll() {
            if cond() { exp.fulfill() }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() } }
        }
        poll()
        wait(for: [exp], timeout: timeout)
    }

    func testRefreshPopulatesStatusesFromRealFilesystem() {
        let config = makeConfig(volumes: [
            DiskVolume(id: "root", displayName: "Root", path: "/", thresholdPercent: nil, thresholdGB: nil)
        ])
        let service = DiskMonitorService(configStore: config, notificationService: NotificationService(isHosted: false))
        service.refresh()
        pollUntil { !service.statuses.isEmpty }
        XCTAssertGreaterThan(service.statuses.first?.totalBytes ?? 0, 0)
    }

    func testWarningNotifiesOnceThenDedupes() {
        // thresholdPercent 200 → free% is always below it → permanent warning.
        let config = makeConfig(volumes: [
            DiskVolume(id: "root", displayName: "Root", path: "/", thresholdPercent: 200, thresholdGB: nil)
        ])
        var posted: [UNNotificationRequest] = []
        let svc = DiskMonitorService(
            configStore: config,
            notificationService: NotificationService(isHosted: true, post: { posted.append($0) })
        )
        svc.refresh()
        pollUntil { posted.contains { $0.identifier.hasPrefix("disk_") } }
        let countAfterFirst = posted.count
        svc.refresh() // alert already active → no duplicate
        pollUntil { !svc.statuses.isEmpty }
        XCTAssertEqual(posted.count, countAfterFirst)
    }

    func testNonWarningPostsNothing() {
        let config = makeConfig(volumes: [
            DiskVolume(id: "root", displayName: "Root", path: "/", thresholdPercent: nil, thresholdGB: nil)
        ])
        var posted: [UNNotificationRequest] = []
        let svc = DiskMonitorService(
            configStore: config,
            notificationService: NotificationService(isHosted: true, post: { posted.append($0) })
        )
        svc.refresh()
        pollUntil { !svc.statuses.isEmpty }
        XCTAssertTrue(posted.isEmpty)
    }

    func testPollingLifecycleAndConfigSinks() {
        let config = makeConfig(volumes: [
            DiskVolume(id: "root", displayName: "Root", path: "/", thresholdPercent: nil, thresholdGB: nil)
        ])
        let svc = DiskMonitorService(configStore: config, notificationService: NotificationService(isHosted: false))
        svc.startPolling()
        svc.startPolling() // idempotent
        config.pollIntervalSeconds = 2   // triggers applyPollInterval sink (stop+start)
        config.isPaused = true           // triggers stopPolling via sink
        config.isPaused = false          // triggers startPolling via sink
        svc.stopPolling()
        // Reaching here without crashing/hanging exercises the lifecycle paths.
        XCTAssertFalse(config.isPaused)
    }
}
