import XCTest
@testable import ProcessMonitor

final class WarningStateTests: XCTestCase {
    func testHasOverLimitProcessReturnsTrueWhenAnyProcessIsOverLimit() {
        let def = ProcessDefinition(
            id: "test",
            displayName: "Test",
            patterns: ["test"],
            defaultLimitMB: 1024
        )
        let running = MonitoredProcess(
            id: "running",
            definition: def,
            status: .running,
            rootPids: [],
            totalMemoryMB: 100,
            totalSwapMB: 0,
            children: [],
            memoryLimitMB: 1024,
            appBundlePath: nil
        )
        let overLimit = MonitoredProcess(
            id: "over",
            definition: def,
            status: .overLimit,
            rootPids: [],
            totalMemoryMB: 2048,
            totalSwapMB: 0,
            children: [],
            memoryLimitMB: 1024,
            appBundlePath: nil
        )

        XCTAssertTrue(hasOverLimitProcess([running, overLimit]))
    }

    func testHasOverLimitProcessReturnsFalseWhenNoProcessIsOverLimit() {
        let def = ProcessDefinition(
            id: "test",
            displayName: "Test",
            patterns: ["test"],
            defaultLimitMB: 1024
        )
        let running = MonitoredProcess(
            id: "running",
            definition: def,
            status: .running,
            rootPids: [],
            totalMemoryMB: 100,
            totalSwapMB: 0,
            children: [],
            memoryLimitMB: 1024,
            appBundlePath: nil
        )
        let notRunning = MonitoredProcess(
            id: "stopped",
            definition: def,
            status: .notRunning,
            rootPids: [],
            totalMemoryMB: 0,
            totalSwapMB: 0,
            children: [],
            memoryLimitMB: 1024,
            appBundlePath: nil
        )

        XCTAssertFalse(hasOverLimitProcess([running, notRunning]))
        XCTAssertFalse(hasOverLimitProcess([]))
    }
}
