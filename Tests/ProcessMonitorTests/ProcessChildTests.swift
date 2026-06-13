import XCTest
@testable import ProcessMonitor

final class ProcessChildTests: XCTestCase {

    // MARK: - formatMemory / formatDiskGB

    func testFormatMemoryMB() {
        XCTAssertEqual(formatMemory(512), "512 MB")
    }

    func testFormatMemoryGB() {
        XCTAssertEqual(formatMemory(2048), "2.0 GB")
    }

    func testFormatDiskGB() {
        XCTAssertEqual(formatDiskGB(42.5), "42.5 GB")
    }

    func testFormatDiskTB() {
        XCTAssertEqual(formatDiskGB(2000), "2.0 TB")
    }

    // MARK: - ProcessChild

    private func child(_ pid: pid_t, mem: Double, swap: Double = 0, cpu: Double = 0, cmd: String = "node") -> ProcessChild {
        ProcessChild(id: pid, parentPid: 1, command: cmd, memoryMB: mem, swapMB: swap, cpuPercent: cpu)
    }

    func testChildFormatting() {
        let c = child(10, mem: 1536, swap: 100, cpu: 12)
        XCTAssertEqual(c.formattedMemory, "1.5 GB")
        XCTAssertEqual(c.formattedSwap, "100 MB")
        XCTAssertEqual(c.formattedCPU, "12%")
    }

    // MARK: - ProcessChildGroup aggregation

    func testGroupAggregates() {
        let group = ProcessChildGroup(name: "node", children: [
            child(1, mem: 100, swap: 10, cpu: 5),
            child(2, mem: 200, swap: 20, cpu: 7)
        ])
        XCTAssertEqual(group.id, "node")
        XCTAssertEqual(group.count, 2)
        XCTAssertEqual(group.totalMemoryMB, 300, accuracy: 0.0001)
        XCTAssertEqual(group.totalSwapMB, 30, accuracy: 0.0001)
        XCTAssertEqual(group.totalCPU, 12, accuracy: 0.0001)
        XCTAssertEqual(group.pids, [1, 2])
        XCTAssertEqual(group.formattedMemory, "300 MB")
        XCTAssertEqual(group.formattedSwap, "30 MB")
        XCTAssertEqual(group.formattedCPU, "12%")
    }

    // MARK: - RawProcessEntry

    func testRawProcessEntryStores() {
        let e = RawProcessEntry(pid: 5, ppid: 1, rssKB: 2048, cpuPercent: 3, command: "/bin/zsh")
        XCTAssertEqual(e.pid, 5)
        XCTAssertEqual(e.ppid, 1)
        XCTAssertEqual(e.rssKB, 2048)
        XCTAssertEqual(e.cpuPercent, 3, accuracy: 0.0001)
        XCTAssertEqual(e.command, "/bin/zsh")
    }
}
