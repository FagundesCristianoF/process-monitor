import XCTest
@testable import ProcessMonitor

final class DiskVolumeTests: XCTestCase {

    private func status(total: Int64, free: Int64, pct: Double? = nil, gb: Double? = nil) -> DiskVolumeStatus {
        let vol = DiskVolume(id: "v", displayName: "Vol", path: "/", thresholdPercent: pct, thresholdGB: gb)
        return DiskVolumeStatus(volume: vol, totalBytes: total, freeBytes: free)
    }

    // MARK: - DiskVolumeStatus math

    func testFreePercent() {
        XCTAssertEqual(status(total: 200, free: 50).freePercent, 25, accuracy: 0.0001)
    }

    func testFreePercentZeroTotalGuards() {
        XCTAssertEqual(status(total: 0, free: 50).freePercent, 0)
    }

    func testGBConversions() {
        let oneGB: Int64 = 1_073_741_824
        let s = status(total: oneGB * 10, free: oneGB * 4)
        XCTAssertEqual(s.totalGB, 10, accuracy: 0.0001)
        XCTAssertEqual(s.freeGB, 4, accuracy: 0.0001)
        XCTAssertEqual(s.usedGB, 6, accuracy: 0.0001)
    }

    // MARK: - isWarning branches

    func testIsWarningByPercent() {
        XCTAssertTrue(status(total: 100, free: 5, pct: 10).isWarning)
    }

    func testIsWarningByGB() {
        let oneGB: Int64 = 1_073_741_824
        XCTAssertTrue(status(total: oneGB * 100, free: oneGB * 2, gb: 5).isWarning)
    }

    func testNotWarningWhenAboveThresholds() {
        let oneGB: Int64 = 1_073_741_824
        XCTAssertFalse(status(total: oneGB * 100, free: oneGB * 50, pct: 10, gb: 5).isWarning)
    }

    func testNotWarningWhenNoThresholds() {
        XCTAssertFalse(status(total: 100, free: 1).isWarning)
    }

    // MARK: - DiskVolume

    func testBootDefault() {
        let boot = DiskVolume.bootDefault
        XCTAssertEqual(boot.id, "root")
        XCTAssertEqual(boot.path, "/")
        XCTAssertEqual(boot.thresholdPercent, 10)
        XCTAssertEqual(boot.thresholdGB, 5)
        XCTAssertFalse(boot.displayName.isEmpty)
    }

    func testVolumeNameForRootIsResolvable() {
        XCTAssertNotNil(DiskVolume.volumeName(for: "/"))
    }

    func testVolumeNameForBogusPathIsNil() {
        XCTAssertNil(DiskVolume.volumeName(for: "/no/such/volume/xyz123"))
    }
}
