import XCTest
@testable import ProcessMonitor

final class DiskUsageScannerTests: XCTestCase {

    func testParseDuLineTabSeparated() {
        let entry = DiskUsageScanner.parseDuLine("23715840\t/Users/me/Library/Developer/Xcode/DerivedData")
        XCTAssertEqual(entry?.bytes, 23715840 * 1024)
        XCTAssertEqual(entry?.path, "/Users/me/Library/Developer/Xcode/DerivedData")
    }

    func testParseDuLineSpaceSeparated() {
        let entry = DiskUsageScanner.parseDuLine("1024 /Users/me/.gradle/caches")
        XCTAssertEqual(entry?.bytes, 1024 * 1024)
        XCTAssertEqual(entry?.path, "/Users/me/.gradle/caches")
    }

    func testParseDuOutputSortsAndLimits() {
        let output = """
        100\t/tmp/small
        9000\t/tmp/large
        500\t/tmp/medium
        """
        let entries = DiskUsageScanner.parseDuOutput(output, limit: 2)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].displayName, "large")
        XCTAssertEqual(entries[1].displayName, "medium")
    }

    func testParseDuLineIgnoresInvalidLines() {
        XCTAssertNil(DiskUsageScanner.parseDuLine(""))
        XCTAssertNil(DiskUsageScanner.parseDuLine("not-a-size"))
    }
}
