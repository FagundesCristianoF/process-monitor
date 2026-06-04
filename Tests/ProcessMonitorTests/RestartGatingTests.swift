import XCTest
@testable import ProcessMonitor

final class RestartGatingTests: XCTestCase {
    private func makeProcess(
        patterns: [String],
        appBundlePath: String?,
        status: ProcessStatus = .running
    ) -> MonitoredProcess {
        let def = ProcessDefinition(
            id: "test",
            displayName: "Test",
            patterns: patterns,
            defaultLimitMB: 1024
        )
        return MonitoredProcess(
            id: def.id,
            definition: def,
            status: status,
            rootPids: [1],
            totalMemoryMB: 0,
            totalSwapMB: 0,
            totalCPU: 0,
            memoryHistory: [],
            cpuHistory: [],
            children: [],
            memoryLimitMB: 1024,
            appBundlePath: appBundlePath,
            startedBy: nil
        )
    }

    // Regression (ed8077f): a user-added app whose pattern lacks ".app" still
    // resolves a real bundle path at runtime and IS restartable. Gating on the
    // pattern text hid the restart option for these apps.
    func testCanRestartWhenBundleResolvedDespitePatternWithoutDotApp() {
        let process = makeProcess(
            patterns: ["Slack"],
            appBundlePath: "/Applications/Slack.app"
        )
        XCTAssertTrue(process.canRestart)
    }

    func testCannotRestartWhenNoBundlePath() {
        let process = makeProcess(patterns: ["java"], appBundlePath: nil)
        XCTAssertFalse(process.canRestart)
    }

    func testCanRestartForBundlePatternApp() {
        let process = makeProcess(
            patterns: ["Cursor.app"],
            appBundlePath: "/Applications/Cursor.app"
        )
        XCTAssertTrue(process.canRestart)
    }
}
