import XCTest
@testable import ProcessMonitor

final class CleanupSizeEstimatorTests: XCTestCase {

    // MARK: - Path-based

    func testSimpleRmRf() {
        let result = CleanupSizeEstimator.measurementCommand(for: "rm -rf ~/.gradle/caches")
        XCTAssertEqual(result, "du -sck ~/.gradle/caches 2>/dev/null | tail -1 | awk '{printf \"%d\", $1*1024}'")
    }

    func testRmF() {
        let result = CleanupSizeEstimator.measurementCommand(for: "rm -f ~/foo.log")
        XCTAssertEqual(result, "du -sck ~/foo.log 2>/dev/null | tail -1 | awk '{printf \"%d\", $1*1024}'")
    }

    func testMultiplePathsInSingleRmClause() {
        let command = #"rm -rf ~/Library/Application\ Support/Cursor/Cache ~/Library/Application\ Support/Cursor/GPUCache"#
        let expected = #"du -sck ~/Library/Application\ Support/Cursor/Cache ~/Library/Application\ Support/Cursor/GPUCache 2>/dev/null | tail -1 | awk '{printf "%d", $1*1024}'"#
        XCTAssertEqual(CleanupSizeEstimator.measurementCommand(for: command), expected)
    }

    func testFindDeletePlusRmClause() {
        let command = #"find ~/Library/Application\ Support/Cursor/User/workspaceStorage -name "state.vscdb*" -delete; rm -f ~/Library/Application\ Support/Cursor/User/globalStorage/state.vscdb*"#
        let expected = #"du -sck ~/Library/Application\ Support/Cursor/User/workspaceStorage ~/Library/Application\ Support/Cursor/User/globalStorage/state.vscdb* 2>/dev/null | tail -1 | awk '{printf "%d", $1*1024}'"#
        XCTAssertEqual(CleanupSizeEstimator.measurementCommand(for: command), expected)
    }

    func testGlobPathPreserved() {
        let result = CleanupSizeEstimator.measurementCommand(for: "rm -rf ~/Library/Developer/Xcode/DerivedData/*")
        XCTAssertEqual(result, "du -sck ~/Library/Developer/Xcode/DerivedData/* 2>/dev/null | tail -1 | awk '{printf \"%d\", $1*1024}'")
    }

    // MARK: - Known-tool heuristics

    func testBrewCleanup() {
        let result = CleanupSizeEstimator.measurementCommand(for: "brew cleanup --prune=all")
        XCTAssertEqual(result, #"command -v brew >/dev/null 2>&1 && du -sk "$(brew --cache)" 2>/dev/null | awk '{printf "%d", $1*1024}'"#)
    }

    func testNpmCacheClean() {
        let result = CleanupSizeEstimator.measurementCommand(for: "npm cache clean --force")
        XCTAssertEqual(result, #"command -v npm >/dev/null 2>&1 && du -sk "$(npm config get cache 2>/dev/null)" 2>/dev/null | awk '{printf "%d", $1*1024}'"#)
    }

    func testPodCacheClean() {
        let result = CleanupSizeEstimator.measurementCommand(for: "pod cache clean --all")
        XCTAssertEqual(result, #"command -v pod >/dev/null 2>&1 && du -sk ~/Library/Caches/CocoaPods 2>/dev/null | awk '{printf "%d", $1*1024}'"#)
    }

    func testDockerSystemPrune() {
        let result = CleanupSizeEstimator.measurementCommand(for: "docker system prune --volumes -f")
        XCTAssertEqual(result, #"command -v docker >/dev/null 2>&1 && docker system df --format '{{.Reclaimable}}' 2>/dev/null | sed -E 's/ *\([0-9]+%\)//' | awk '/TB$/{gsub(/TB$/,"");sum+=$1*1099511627776} /GB$/{gsub(/GB$/,"");sum+=$1*1073741824} /MB$/{gsub(/MB$/,"");sum+=$1*1048576} /kB$/{gsub(/kB$/,"");sum+=$1*1024} /B$/{gsub(/B$/,"");sum+=$1} END{printf "%d", sum}'"#)
    }

    func testSimctlDeleteUnavailable() {
        let result = CleanupSizeEstimator.measurementCommand(for: "xcrun simctl delete unavailable")
        XCTAssertEqual(result, #"xcrun simctl list devices unavailable 2>/dev/null | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' | while read -r id; do du -sk "$HOME/Library/Developer/CoreSimulator/Devices/$id" 2>/dev/null; done | awk '{sum+=$1} END{printf "%d", sum*1024}'"#)
    }

    func testSimctlEraseAll() {
        let result = CleanupSizeEstimator.measurementCommand(for: "xcrun simctl shutdown all 2>/dev/null; xcrun simctl erase all")
        XCTAssertEqual(result, #"xcrun simctl list devices 2>/dev/null | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' | while read -r id; do du -sk "$HOME/Library/Developer/CoreSimulator/Devices/$id" 2>/dev/null; done | awk '{sum+=$1} END{printf "%d", sum*1024}'"#)
    }

    // MARK: - No estimator applies

    func testPlainCommandHasNoEstimator() {
        XCTAssertNil(CleanupSizeEstimator.measurementCommand(for: "echo hello"))
    }

    func testScanCommandHasNoEstimator() {
        let scan = #"find ~ -path "$HOME/Library" -prune -o -type d \( -name build -o -name DerivedData \) -prune -exec du -sh {} + 2>/dev/null | sort -rh | head -30"#
        // Contains "find" but with no "-delete" flag — must not match the find-path heuristic.
        XCTAssertNil(CleanupSizeEstimator.measurementCommand(for: scan))
    }
}
