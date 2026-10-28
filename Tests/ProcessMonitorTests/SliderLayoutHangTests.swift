import XCTest
import SwiftUI
import AppKit
@testable import ProcessMonitor

// PROCESS-MONITOR-6/-P/-N/-M/-K/-9 regression: Slider(step:) builds an NSSlider with a
// tick mark per step; -[NSSliderTickMarks _rebuildTickMarkRectCache] recursed through
// layout and blocked the main thread ≥2000 ms. SnappedSlider drops `step:` (no ticks).

@MainActor
final class SliderLayoutHangTests: XCTestCase {

    private static let hangThreshold: TimeInterval = 2.0

    private struct Ranges: View {
        let snapped: Bool
        @State private var a = 64.0
        @State private var b = 5.0
        @State private var c = 10.0
        @State private var d = 30.0

        var body: some View {
            VStack(spacing: 8) {
                slider($a, 64...32768, 64)
                slider($b, 1...500, 1)
                slider($c, 1...1440, 1)
                slider($d, 1...60, 1)
            }
            .padding()
        }

        @ViewBuilder
        private func slider(_ v: Binding<Double>, _ r: ClosedRange<Double>, _ s: Double) -> some View {
            if snapped {
                SnappedSlider(value: v, range: r, step: s)
            } else {
                Slider(value: v, in: r, step: s)
            }
        }
    }

    /// Hosts the view in a real window and returns wall time of a full layout + display pass.
    private func layoutTime(snapped: Bool) -> TimeInterval {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: Ranges(snapped: snapped))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView = host

        let start = CFAbsoluteTimeGetCurrent()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        _ = host.fittingSize
        return CFAbsoluteTimeGetCurrent() - start
    }

    func testSnappedSliderLayoutDoesNotHang() {
        let elapsed = layoutTime(snapped: true)
        XCTAssertLessThan(elapsed, Self.hangThreshold, "SnappedSlider layout took \(elapsed)s")
    }

    /// Reproduction: documents the original hang. Skipped if this OS doesn't exhibit it.
    func testSteppedSliderReproducesHang() throws {
        let elapsed = layoutTime(snapped: false)
        let snapped = layoutTime(snapped: true)
        try XCTSkipIf(elapsed < snapped * 3, "Slider(step:) not slower on this OS (\(elapsed)s vs \(snapped)s)")
        XCTAssertGreaterThan(elapsed, snapped * 3)
        print("Slider(step:) \(elapsed)s vs SnappedSlider \(snapped)s")
    }

    /// Deterministic guard: no view may use `Slider(... step:)` directly (tick-mark hang).
    func testNoRawSteppedSliderInViews() throws {
        let views = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ProcessMonitor/Views")
        let files = try FileManager.default.contentsOfDirectory(at: views, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let pattern = try NSRegularExpression(pattern: #"(?<![A-Za-z])Slider\((?:[^()]|\([^()]*\))*step:"#)
        for file in files {
            let src = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            let hits = pattern.numberOfMatches(in: src, range: NSRange(src.startIndex..., in: src))
            XCTAssertEqual(hits, 0, "\(file.lastPathComponent): use SnappedSlider instead of Slider(step:)")
        }
    }

    func testSnapsToStepAndClamps() {
        var value = 64.0
        let s = SnappedSlider(value: Binding(get: { value }, set: { value = $0 }), range: 64...32768, step: 64)
        XCTAssertEqual(s.snapped(100), 128)
        XCTAssertEqual(s.snapped(99999), 32768)
        XCTAssertEqual(s.snapped(-5), 64)
    }
}
