import XCTest
@testable import ProcessMonitor

final class AppInfoTests: XCTestCase {
    func testDisplayVersionFormat() {
        XCTAssertEqual(AppInfo.displayVersion(version: "1.3.1", build: "5"), "1.3.1 (5)")
    }

    func testBugReportURLIsGitHubNewIssue() {
        let url = AppInfo.bugReportURL(
            version: "1.3.1",
            build: "5",
            osVersion: "Version 15.0 (Build 24A335)"
        )
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/FagundesCristianoF/process-monitor/issues/new")
    }

    func testBugReportURLEncodesVersionAndOSInBody() {
        let url = AppInfo.bugReportURL(
            version: "1.3.1",
            build: "5",
            osVersion: "Version 15.0 (Build 24A335)"
        )
        // Decode the body query item back and assert it carries the diagnostics.
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let body = comps?.queryItems?.first(where: { $0.name == "body" })?.value
        XCTAssertNotNil(body)
        XCTAssertTrue(body!.contains("1.3.1 (5)"), "body should include the app version/build")
        XCTAssertTrue(body!.contains("Version 15.0 (Build 24A335)"), "body should include the macOS version")
    }

    // MARK: - Bundle-backed accessors (no .app bundle in tests → em-dash fallback)

    func testRepositoryURL() {
        XCTAssertEqual(AppInfo.repositoryURL.host, "github.com")
    }

    func testVersionAndBuildAccessorsReturnNonEmpty() {
        XCTAssertFalse(AppInfo.version.isEmpty)
        XCTAssertFalse(AppInfo.build.isEmpty)
    }

    func testDisplayVersionAccessorMatchesComponents() {
        XCTAssertEqual(AppInfo.displayVersion, "\(AppInfo.version) (\(AppInfo.build))")
    }

    func testBugReportURLAccessorIsNewIssue() {
        XCTAssertEqual(AppInfo.bugReportURL.path, "/FagundesCristianoF/process-monitor/issues/new")
    }
}
