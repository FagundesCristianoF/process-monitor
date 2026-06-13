import XCTest
import Sentry
@testable import ProcessMonitor

/// Note: Telemetry.start(enabled: true) / capture would boot the real Sentry SDK
/// against the production DSN, so those paths are intentionally not exercised
/// here. We cover the privacy-scrubbing logic (the part that matters for
/// correctness) plus the safe no-op guards.
final class TelemetryServiceTests: XCTestCase {

    private struct DummyError: Error {}

    // MARK: - Safe guards (telemetry not started)

    func testStartDisabledIsNoOp() {
        Telemetry.start(enabled: false) // guarded → does nothing, must not crash
    }

    func testSetEnabledFalseStopsSafely() {
        Telemetry.setEnabled(false)
    }

    func testCaptureWhenNotStarted() {
        Telemetry.capture(DummyError(), context: "unit-test")
        Telemetry.capture(DummyError())
    }

    func testCaptureMessageWhenNotStarted() {
        Telemetry.captureMessage("hello", level: .warning)
    }

    func testBreadcrumbDoesNotCrash() {
        Telemetry.breadcrumb("did a thing", category: "test")
    }

    // MARK: - Privacy scrubbing

    func testScrubRemovesProcessKeysFromBreadcrumb() {
        let crumb = Breadcrumb(level: .info, category: "test")
        crumb.data = ["process": "Cursor", "command": "java -jar", "processName": "x", "keep": "ok"]
        Telemetry.scrub(crumb)
        XCTAssertNil(crumb.data?["process"])
        XCTAssertNil(crumb.data?["command"])
        XCTAssertNil(crumb.data?["processName"])
        XCTAssertEqual(crumb.data?["keep"] as? String, "ok")
    }

    func testScrubRemovesProcessKeysFromEvent() {
        let event = Event()
        event.extra = ["process": "Cursor", "command": "node", "processName": "y", "keep": "ok"]
        let crumb = Breadcrumb(level: .info, category: "c")
        crumb.data = ["command": "secret"]
        event.breadcrumbs = [crumb]

        Telemetry.scrub(event)

        XCTAssertNil(event.extra?["process"])
        XCTAssertNil(event.extra?["command"])
        XCTAssertNil(event.extra?["processName"])
        XCTAssertEqual(event.extra?["keep"] as? String, "ok")
        XCTAssertNil(event.breadcrumbs?.first?.data?["command"], "nested breadcrumbs scrubbed too")
    }
}
