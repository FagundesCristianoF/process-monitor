import XCTest
@testable import ProcessMonitor

@MainActor
final class UpdaterServiceTests: XCTestCase {
    // Sparkle's SPUStandardUpdaterController aborts the test process when started
    // without a valid host bundle / SUFeedURL / SUPublicEDKey. Flag the test env so
    // UpdaterService constructs the controller without starting the live updater.
    override class func setUp() {
        super.setUp()
        setenv("PM_TESTING", "1", 1)
    }

    func testStartsWithAutomaticChecksEnabled() {
        let service = UpdaterService()
        XCTAssertTrue(service.automaticallyChecksForUpdates,
                      "Updater should auto-check by default for silent updates")
    }

    func testStartsWithAutomaticDownloadEnabled() {
        let service = UpdaterService()
        XCTAssertTrue(service.automaticallyDownloadsUpdates,
                      "Updater should auto-download for silent updates")
    }

    func testCanCheckForUpdatesIsExposed() {
        let service = UpdaterService()
        _ = service.canCheckForUpdates
    }
}
