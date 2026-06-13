import XCTest
import AppKit
@testable import ProcessMonitor

final class AppIconResolverTests: XCTestCase {

    func testIconAtNonexistentPathIsNil() {
        XCTAssertNil(AppIconResolver.icon(atPath: "/no/such/path-\(UUID().uuidString).app"))
    }

    func testIconAtRealPathResolvesAndCaches() {
        // "/" always exists; NSWorkspace returns a (generic) icon for any real path.
        let first = AppIconResolver.icon(atPath: "/")
        XCTAssertNotNil(first)
        let second = AppIconResolver.icon(atPath: "/") // cache hit branch
        XCTAssertNotNil(second)
    }

    func testIconForBogusDefinitionIsNil() {
        let def = ProcessDefinition(
            id: "ghost",
            displayName: "DefinitelyNotInstalled-\(UUID().uuidString)",
            patterns: ["DefinitelyNotInstalled-\(UUID().uuidString).app"],
            defaultLimitMB: 512
        )
        XCTAssertNil(AppIconResolver.icon(for: def))
    }

    func testIconForDefinitionDoesNotCrashOnLookup() {
        // Exercises the search-path + NSWorkspace fallback branches; result is
        // environment-dependent so we only assert it returns without crashing.
        let def = ProcessDefinition(id: "finder", displayName: "Finder", patterns: ["Finder.app"], defaultLimitMB: 512)
        _ = AppIconResolver.icon(for: def)
    }

    @MainActor
    func testAppIconBadgeBodyEvaluates() {
        // Smoke-evaluate both the resolved-icon and placeholder branches.
        _ = AppIconBadge(definition: nil, bundlePath: "/").body
        let def = ProcessDefinition(id: "ghost", displayName: "Ghost-\(UUID().uuidString)", patterns: [], defaultLimitMB: 1)
        _ = AppIconBadge(definition: def, bundlePath: nil, size: 16, dimmed: true).body
    }
}
