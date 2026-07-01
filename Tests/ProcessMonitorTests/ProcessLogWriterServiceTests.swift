import XCTest
@testable import ProcessMonitor

final class ProcessLogWriterServiceTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PMLogWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeProcess(
        id: String = "cursor",
        status: ProcessStatus = .running,
        cpu: Double = 12.3,
        memoryMB: Double = 256.7,
        swapMB: Double = 1.2,
        childCount: Int = 2
    ) -> MonitoredProcess {
        let definition = ProcessDefinition(
            id: id, displayName: id, patterns: [id], defaultLimitMB: 1024
        )
        let children: [ProcessChild] = (0..<childCount).map {
            ProcessChild(id: pid_t(1000 + $0), parentPid: 1, command: "child\($0)", memoryMB: 10, swapMB: 0, cpuPercent: 1)
        }
        return MonitoredProcess(
            id: id,
            definition: definition,
            status: status,
            rootPids: [999],
            totalMemoryMB: memoryMB,
            totalSwapMB: swapMB,
            totalCPU: cpu,
            memoryHistory: [],
            cpuHistory: [],
            children: children,
            memoryLimitMB: 1024,
            appBundlePath: nil,
            startedBy: nil
        )
    }

    func testLogCreatesFileWithHeaderAndFirstRow() {
        let writer = ProcessLogWriterService(logsDirectory: tempDir)
        writer.log(process: makeProcess())

        let fileURL = tempDir.appendingPathComponent("cursor.csv")
        let contents = try! String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "timestamp,cpu_percent,memory_mb,swap_mb,process_count")
        XCTAssertTrue(lines[1].hasSuffix(",12.3,256.7,1.2,3"))
    }

    func testSecondLogAppendsWithoutRepeatingHeader() {
        let writer = ProcessLogWriterService(logsDirectory: tempDir)
        writer.log(process: makeProcess())
        writer.log(process: makeProcess())

        let fileURL = tempDir.appendingPathComponent("cursor.csv")
        let contents = try! String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "timestamp,cpu_percent,memory_mb,swap_mb,process_count")
    }

    func testFileSizeBytesNilBeforeWriteNonNilAfter() {
        let writer = ProcessLogWriterService(logsDirectory: tempDir)
        XCTAssertNil(writer.fileSizeBytes(forAppID: "cursor"))

        writer.log(process: makeProcess())
        XCTAssertNotNil(writer.fileSizeBytes(forAppID: "cursor"))
    }

    func testClearLogTruncatesToHeaderOnly() {
        let writer = ProcessLogWriterService(logsDirectory: tempDir)
        writer.log(process: makeProcess())
        writer.log(process: makeProcess())
        let sizeBeforeClear = writer.fileSizeBytes(forAppID: "cursor")!

        writer.clearLog(forAppID: "cursor")
        let sizeAfterClear = writer.fileSizeBytes(forAppID: "cursor")!

        XCTAssertLessThan(sizeAfterClear, sizeBeforeClear)

        let fileURL = tempDir.appendingPathComponent("cursor.csv")
        let contents = try! String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(contents, "timestamp,cpu_percent,memory_mb,swap_mb,process_count\n")
    }

    func testLogNoOpWhenNotRunning() {
        let writer = ProcessLogWriterService(logsDirectory: tempDir)
        writer.log(process: makeProcess(status: .notRunning))

        XCTAssertNil(writer.fileSizeBytes(forAppID: "cursor"))
    }
}
