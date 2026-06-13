import XCTest
@testable import ProcessMonitor

@MainActor
final class UpdaterServiceTests: XCTestCase {
    // Pass startUpdater: false — Sparkle's SPUStandardUpdaterController aborts the test
    // process when started without a valid host bundle / SUFeedURL / SUPublicEDKey.
    func testStartsWithAutomaticChecksEnabled() {
        let service = UpdaterService(startUpdater: false)
        XCTAssertTrue(service.automaticallyChecksForUpdates,
                      "Updater should auto-check by default for silent updates")
    }

    func testStartsWithAutomaticDownloadEnabled() {
        let service = UpdaterService(startUpdater: false)
        XCTAssertTrue(service.automaticallyDownloadsUpdates,
                      "Updater should auto-download for silent updates")
    }

    /// Regression guard: a malformed SUPublicEDKey makes Sparkle's updater fail to
    /// start ("The updater failed to start"). The key must decode to a 32-byte
    /// Ed25519 public key, and must not be the build placeholder.
    func testInfoPlistHasValidEdDSAPublicKey() throws {
        // Walk up from this file to the repo root (the dir containing Package.swift),
        // so the test survives directory restructuring.
        var repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("Package.swift").path) {
            let parent = repoRoot.deletingLastPathComponent()
            guard parent != repoRoot else {
                XCTFail("Could not locate repo root (Package.swift) from \(#filePath)")
                return
            }
            repoRoot = parent
        }
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
