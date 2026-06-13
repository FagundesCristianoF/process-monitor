import XCTest
@testable import ProcessMonitor

final class MonitoredProcessTests: XCTestCase {

    private func def(patterns: [String]) -> ProcessDefinition {
        ProcessDefinition(id: "t", displayName: "T", patterns: patterns, defaultLimitMB: 1024)
    }

    // MARK: - ProcessDefinition

    func testMatchesCaseInsensitiveContains() {
        XCTAssertTrue(def(patterns: ["java"]).matches(command: "/usr/bin/JAVA -jar app"))
    }

    func testDoesNotMatch() {
        XCTAssertFalse(def(patterns: ["gradle"]).matches(command: "/usr/bin/node"))
    }

    func testIsRestartableWithDotApp() {
        XCTAssertTrue(def(patterns: ["Cursor.app"]).isRestartable)
    }

    func testIsNotRestartableWithoutDotApp() {
        XCTAssertFalse(def(patterns: ["java"]).isRestartable)
    }

    func testBuiltInDefaultsValid() {
        let defs = ProcessDefinition.builtInDefaults
        XCTAssertFalse(defs.isEmpty)
        XCTAssertEqual(Set(defs.map(\.id)).count, defs.count, "ids unique")
        XCTAssertTrue(defs.allSatisfy { $0.defaultLimitMB > 0 })
    }

    // MARK: - MonitoredProcess formatting

    private func process(status: ProcessStatus, mem: Double = 2048, swap: Double = 512, cpu: Double = 25, children: [ProcessChild] = []) -> MonitoredProcess {
        MonitoredProcess(
            id: "t", definition: def(patterns: ["java"]), status: status,
            rootPids: [1], totalMemoryMB: mem, totalSwapMB: swap, totalCPU: cpu,
            memoryHistory: [], cpuHistory: [], children: children,
            memoryLimitMB: 4096, appBundlePath: nil, startedBy: nil
        )
    }

    func testFormattingWhenRunning() {
        let p = process(status: .running)
        XCTAssertEqual(p.formattedMemory, "2.0 GB")
        XCTAssertEqual(p.formattedSwap, "512 MB")
        XCTAssertEqual(p.formattedCPU, "25%")
        XCTAssertEqual(p.formattedLimit, "4.0 GB")
    }

    func testFormattingWhenNotRunningShowsDash() {
        let p = process(status: .notRunning)
        XCTAssertEqual(p.formattedMemory, "--")
        XCTAssertEqual(p.formattedSwap, "--")
        XCTAssertEqual(p.formattedCPU, "--")
    }

    func testChildGroupsGroupedAndSortedByMemory() {
        let children = [
            ProcessChild(id: 1, parentPid: 1, command: "node", memoryMB: 50, swapMB: 0, cpuPercent: 0),
            ProcessChild(id: 2, parentPid: 1, command: "node", memoryMB: 100, swapMB: 0, cpuPercent: 0),
            ProcessChild(id: 3, parentPid: 1, command: "ruby", memoryMB: 500, swapMB: 0, cpuPercent: 0)
        ]
        let groups = process(status: .running, children: children).childGroups
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.name, "ruby", "highest total memory first")
        XCTAssertEqual(groups.first(where: { $0.name == "node" })?.totalMemoryMB, 150)
    }
}
