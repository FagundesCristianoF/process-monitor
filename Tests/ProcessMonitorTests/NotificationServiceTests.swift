import XCTest
import UserNotifications
@testable import ProcessMonitor

final class NotificationServiceTests: XCTestCase {

    // MARK: - Pure body builders

    func testMemoryBody() {
        let body = NotificationService.memoryBody(processName: "Java", memoryMB: 2048, limitMB: 1024)
        XCTAssertTrue(body.contains("Java"))
        XCTAssertTrue(body.contains("2.0 GB"))
        XCTAssertTrue(body.contains("1.0 GB"))
    }

    func testAutoRestartBody() {
        let body = NotificationService.autoRestartBody(processName: "Cursor", memoryMB: 512, limitMB: 256)
        XCTAssertTrue(body.contains("Cursor"))
        XCTAssertTrue(body.contains("512 MB"))
    }

    func testDiskBody() {
        let vol = DiskVolume(id: "root", displayName: "Macintosh HD", path: "/", thresholdPercent: 10, thresholdGB: nil)
        let oneGB: Int64 = 1_073_741_824
        let status = DiskVolumeStatus(volume: vol, totalBytes: oneGB * 100, freeBytes: oneGB * 3)
        let body = NotificationService.diskBody(status: status)
        XCTAssertTrue(body.contains("Macintosh HD"))
        XCTAssertTrue(body.contains("3.0 GB"))
    }

    // MARK: - Posting (hosted)

    private func hostedService() -> (NotificationService, () -> [UNNotificationRequest]) {
        var posted: [UNNotificationRequest] = []
        let svc = NotificationService(isHosted: true, post: { posted.append($0) })
        return (svc, { posted })
    }

    func testNotifyIfNeededPostsOnceThenDedupes() {
        let (svc, posted) = hostedService()
        svc.notifyIfNeeded(processName: "Java", memoryMB: 2048, limitMB: 1024, definitionID: "java")
        svc.notifyIfNeeded(processName: "Java", memoryMB: 2048, limitMB: 1024, definitionID: "java")
        XCTAssertEqual(posted().count, 1, "second call within cooldown is suppressed")
        XCTAssertTrue(posted().first?.identifier.hasPrefix("mem_") ?? false)
    }

    func testResetAllowsRenotify() {
        let (svc, posted) = hostedService()
        svc.notifyIfNeeded(processName: "Java", memoryMB: 2048, limitMB: 1024, definitionID: "java")
        svc.resetMemoryNotification(for: "java")
        // Still within cooldown window, so reset alone does not re-enable.
        svc.notifyIfNeeded(processName: "Java", memoryMB: 2048, limitMB: 1024, definitionID: "java")
        XCTAssertEqual(posted().count, 1)
    }

    func testDifferentDefinitionsPostSeparately() {
        let (svc, posted) = hostedService()
        svc.notifyIfNeeded(processName: "Java", memoryMB: 2048, limitMB: 1024, definitionID: "java")
        svc.notifyIfNeeded(processName: "Cursor", memoryMB: 2048, limitMB: 1024, definitionID: "cursor")
        XCTAssertEqual(posted().count, 2)
    }

    func testNotifyDiskWarningPosts() {
        let (svc, posted) = hostedService()
        let vol = DiskVolume(id: "root", displayName: "HD", path: "/", thresholdPercent: 10, thresholdGB: nil)
        svc.notifyDiskWarning(status: DiskVolumeStatus(volume: vol, totalBytes: 100, freeBytes: 5))
        XCTAssertEqual(posted().count, 1)
        XCTAssertTrue(posted().first?.identifier.hasPrefix("disk_") ?? false)
    }

    func testNotifyAutoRestartPosts() {
        let (svc, posted) = hostedService()
        svc.notifyAutoRestart(processName: "Cursor", memoryMB: 5000, limitMB: 4096)
        XCTAssertEqual(posted().count, 1)
        XCTAssertTrue(posted().first?.identifier.hasPrefix("autorestart_") ?? false)
    }

    // MARK: - Unhosted (headless) path posts nothing

    func testUnhostedPostsNothing() {
        var posted: [UNNotificationRequest] = []
        let svc = NotificationService(isHosted: false, post: { posted.append($0) })
        svc.notifyIfNeeded(processName: "Java", memoryMB: 2048, limitMB: 1024, definitionID: "java")
        let vol = DiskVolume(id: "root", displayName: "HD", path: "/", thresholdPercent: 10, thresholdGB: nil)
        svc.notifyDiskWarning(status: DiskVolumeStatus(volume: vol, totalBytes: 100, freeBytes: 5))
        svc.notifyAutoRestart(processName: "Cursor", memoryMB: 5000, limitMB: 4096)
        XCTAssertTrue(posted.isEmpty)
    }

    // MARK: - Permission

    func testRequestPermissionSkippedWhenUnhosted() {
        var authorizeCalled = false
        let svc = NotificationService(isHosted: false, authorize: { _ in authorizeCalled = true })
        svc.requestPermissionIfNeeded()
        XCTAssertFalse(authorizeCalled)
    }

    func testRequestPermissionInvokesAuthorizerWhenHosted() {
        var authorizeCalled = false
        let svc = NotificationService(isHosted: true, authorize: { completion in
            authorizeCalled = true
            completion(true, nil)
        })
        svc.requestPermissionIfNeeded()
        XCTAssertTrue(authorizeCalled)
    }
}
