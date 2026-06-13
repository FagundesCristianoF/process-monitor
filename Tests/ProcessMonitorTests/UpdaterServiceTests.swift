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

    /// Regression guard: a malformed SUPublicEDKey makes Sparkle's updater fail to
    /// start ("The updater failed to start"). The key must decode to a 32-byte
    /// Ed25519 public key, and must not be the build placeholder.
    func testInfoPlistHasValidEdDSAPublicKey() throws {
        // Tests/ProcessMonitorTests/UpdaterServiceTests.swift -> repo root is 3 dirs up.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = repoRoot.appendingPathComponent("Info.plist")

        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let key = try XCTUnwrap(plist["SUPublicEDKey"] as? String, "SUPublicEDKey missing")

        XCTAssertNotEqual(key, "REPLACE_WITH_ED_PUBLIC_KEY",
                          "SUPublicEDKey is still the build placeholder")
        let decoded = try XCTUnwrap(Data(base64Encoded: key),
                                    "SUPublicEDKey is not valid base64")
        XCTAssertEqual(decoded.count, 32,
                       "Ed25519 public key must be 32 bytes, got \(decoded.count)")
    }
}
