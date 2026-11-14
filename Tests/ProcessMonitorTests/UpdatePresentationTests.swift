import XCTest
@testable import ProcessMonitor

final class UpdatePresentationTests: XCTestCase {
    private let normal = AvailableUpdate(version: "1.16.0", isCritical: false)
    private let critical = AvailableUpdate(version: "1.16.0", isCritical: true)

    func testNoUpdateResolvesToNone() {
        XCTAssertEqual(UpdatePresentation.resolve(available: nil, dismissedThisSession: false), .none)
        XCTAssertEqual(UpdatePresentation.resolve(available: nil, dismissedThisSession: true), .none)
    }

    func testNonCriticalUpdateSuggestsBanner() {
        XCTAssertEqual(
            UpdatePresentation.resolve(available: normal, dismissedThisSession: false),
            .suggest(normal)
        )
    }

    func testNonCriticalDismissedResolvesToNone() {
        XCTAssertEqual(
            UpdatePresentation.resolve(available: normal, dismissedThisSession: true),
            .none
        )
    }

    func testCriticalUpdateIsForced() {
        XCTAssertEqual(
            UpdatePresentation.resolve(available: critical, dismissedThisSession: false),
            .forced(critical)
        )
    }

    func testCriticalDismissedIsStillForced() {
        XCTAssertEqual(
            UpdatePresentation.resolve(available: critical, dismissedThisSession: true),
            .forced(critical)
        )
    }

    /// Release pipeline guard: the workflow must be able to mark a release
    /// critical (`--critical-update-version`), gated on the `[force-update]`
    /// marker line in the HEAD commit message.
    func testReleaseWorkflowSupportsCriticalUpdates() throws {
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
        let yamlURL = repoRoot.appendingPathComponent(".github/workflows/release.yml")

        let yaml = try String(contentsOf: yamlURL, encoding: .utf8)

        XCTAssertTrue(
            yaml.contains("--critical-update-version"),
            "release.yml must pass --critical-update-version to generate_appcast"
        )
        XCTAssertTrue(
            yaml.contains("[force-update]"),
            "release.yml must detect the [force-update] marker line in the HEAD commit message"
        )
    }
}
