import XCTest
@testable import ProcessMonitor

// PM-8 / PM-7 regression: chooseApp() called NSOpenPanel.runModal() on the main
// thread, blocking the run loop ≥2000 ms. Fix extracts picker business logic into
// AppPickerSelection (testable) and replaces runModal with panel.begin(completion:).

final class AppPickerSelectionTests: XCTestCase {

    func testPathEqualsURLPath() {
        let url = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        let sel = AppPickerSelection(url: url)
        XCTAssertEqual(sel.path, "/System/Applications/TextEdit.app")
    }

    func testPatternCandidateHasDotAppSuffix() {
        let url = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
        let sel = AppPickerSelection(url: url)
        XCTAssertEqual(sel.patternCandidate, "Visual Studio Code.app")
    }

    func testExtractsBundleNameFromRealApp() {
        // TextEdit ships on every Mac; its CFBundleName is "TextEdit".
        let url = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        let sel = AppPickerSelection(url: url)
        XCTAssertFalse(sel.suggestedName.isEmpty)
    }

    func testFallsBackToFilenameWhenBundleMissing() {
        let name = "FakeApp-\(UUID().uuidString)"
        let url = URL(fileURLWithPath: "/tmp/\(name).app")
        let sel = AppPickerSelection(url: url)
        XCTAssertEqual(sel.suggestedName, name)
    }

    func testMergedPatternsReturnsPatternForEmptyInput() {
        let sel = AppPickerSelection(url: URL(fileURLWithPath: "/Applications/TextEdit.app"))
        XCTAssertEqual(sel.mergedPatterns(into: ""), "TextEdit.app")
    }

    func testMergedPatternsAppendsWhenPatternMissing() {
        let sel = AppPickerSelection(url: URL(fileURLWithPath: "/Applications/TextEdit.app"))
        XCTAssertEqual(sel.mergedPatterns(into: "safari"), "safari, TextEdit.app")
    }

    func testMergedPatternsSkipsDuplicates() {
        let sel = AppPickerSelection(url: URL(fileURLWithPath: "/Applications/TextEdit.app"))
        let existing = "TextEdit.app, safari"
        XCTAssertEqual(sel.mergedPatterns(into: existing), existing)
    }

    func testMergedPatternsTrimsWhitespaceBeforeComparison() {
        let sel = AppPickerSelection(url: URL(fileURLWithPath: "/Applications/TextEdit.app"))
        XCTAssertEqual(sel.mergedPatterns(into: "  "), "TextEdit.app")
    }
}
