import XCTest
import Combine
import UserNotifications
@testable import ProcessMonitor

final class ProcessMonitorServiceExtraTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PMServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeConfig() -> ProcessConfigStore {
        ProcessConfigStore(
            configFileURL: tempDir.appendingPathComponent("config.json"),
            defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        )
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

    private func dummyFactory(_ interval: TimeInterval) -> Timer.TimerPublisher {
        Timer.publish(every: interval, on: .main, in: .common)
    }

    // MARK: - Static helpers

    func testAppBundlePath() {
        XCTAssertEqual(
            ProcessMonitorService.appBundlePath(from: "/Applications/Cursor.app/Contents/MacOS/Cursor"),
            "/Applications/Cursor.app"
        )
        XCTAssertNil(ProcessMonitorService.appBundlePath(from: "/usr/bin/java"))
    }

    func testFriendlyStarterName() {
        XCTAssertEqual(
            ProcessMonitorService.friendlyStarterName(from: "/Applications/Warp.app/Contents/MacOS/stable"),
            "Warp"
        )
        XCTAssertEqual(ProcessMonitorService.friendlyStarterName(from: "/usr/bin/zsh"), "zsh")
    }

    // MARK: - Real fetch path

    func testRealRefreshPopulatesProcesses() {
        let config = makeConfig()
        let service = ProcessMonitorService(
            configStore: config,
            notificationService: NotificationService(isHosted: false),
            pollInterval: 3600
        )
        service.refresh()
        pollUntil { service.processes.count == config.definitions.count }
        // Second refresh exercises the CPU-delta branch (previousSampleTime > 0).
        service.refresh()
        pollUntil { service.processes.count == config.definitions.count }
    }

    // MARK: - Injected entries: running, startedBy, overLimit → notification

    func testOverLimitTriggersMemoryNotification() {
        let config = makeConfig()
        config.setLimit(-1, for: "java") // force overLimit regardless of measured memory
        var posted: [UNNotificationRequest] = []

        let entries: [RawProcessEntry] = [
            RawProcessEntry(pid: 9990, ppid: 1, rssKB: 0, cpuPercent: 0, command: "/Applications/Warp.app/Contents/MacOS/stable"),
            RawProcessEntry(pid: 9991, ppid: 9990, rssKB: 0, cpuPercent: 5, command: "/usr/bin/java"),
            RawProcessEntry(pid: 9992, ppid: 9991, rssKB: 0, cpuPercent: 1, command: "/usr/bin/node")
        ]

        let service = ProcessMonitorService(
            configStore: config,
            notificationService: NotificationService(isHosted: true, post: { posted.append($0) }),
            pollInterval: 3600,
            processEntriesProvider: { entries },
            pollPublisherFactory: dummyFactory
        )
        service.refresh()
        pollUntil { posted.contains { $0.identifier.hasPrefix("mem_") } }

        let java = service.processes.first { $0.id == "java" }
        XCTAssertEqual(java?.status, .overLimit)
        XCTAssertEqual(java?.startedBy, "Warp")
    }

    // MARK: - Injected entries: nothing running, reset path after repeated ticks

    func testNoEntriesMarksAllNotRunningAndResetsNotification() {
        let config = makeConfig()
        let service = ProcessMonitorService(
            configStore: config,
            notificationService: NotificationService(isHosted: false),
            pollInterval: 3600,
            processEntriesProvider: { [] },
            pollPublisherFactory: dummyFactory
        )
        // Multiple refreshes drive belowLimitTickCount past the reset threshold.
        for _ in 0..<(ProcessMonitorService.belowLimitTicksRequired + 1) {
            service.refresh()
            pollUntil { service.processes.count == config.definitions.count }
        }
        XCTAssertTrue(service.processes.allSatisfy { $0.status == .notRunning })
    }

    // MARK: - Kill / restart

    private func makeProcess(appBundlePath: String?) -> MonitoredProcess {
        let def = ProcessDefinition(id: "java", displayName: "Java", patterns: ["java"], defaultLimitMB: 1024)
        return MonitoredProcess(
            id: def.id, definition: def, status: .running,
            rootPids: [999_990], totalMemoryMB: 0, totalSwapMB: 0, totalCPU: 0,
            memoryHistory: [], cpuHistory: [], children: [],
            memoryLimitMB: 1024, appBundlePath: appBundlePath, startedBy: nil
        )
    }

    func testKillMethodsDoNotCrash() {
        let service = ProcessMonitorService(
            configStore: makeConfig(),
            notificationService: NotificationService(isHosted: false),
            pollInterval: 3600,
            processEntriesProvider: { [] }
        )
        // Non-existent PIDs: kill() returns an error that is intentionally ignored.
        service.killProcess(pid: 999_991)
        service.killProcesses(pids: [999_992, 999_993])
        service.killGroup(makeProcess(appBundlePath: nil))
    }

    func testRestartGroupHandlesBothBundlePresenceCases() {
        let service = ProcessMonitorService(
            configStore: makeConfig(),
            notificationService: NotificationService(isHosted: false),
            pollInterval: 3600,
            processEntriesProvider: { [] }
        )
        service.restartGroup(makeProcess(appBundlePath: nil))
        service.restartGroup(makeProcess(appBundlePath: "/no/such/App-\(UUID().uuidString).app"))
    }
}
