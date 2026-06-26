import XCTest
import AppKit
@testable import ProcessMonitor

final class AppIconResolverTests: XCTestCase {

    // MARK: - loadAsync(atPath:)

    func testLoadAsyncReturnsNilForNonexistentPath() async {
        let result = await AppIconResolver.loadAsync(atPath: "/no/such/path-\(UUID().uuidString).app")
        XCTAssertNil(result)
    }

    func testLoadAsyncReturnsImageForRealPath() async {
        // "/" always exists; NSWorkspace returns a generic icon for any real path.
        let result = await AppIconResolver.loadAsync(atPath: "/")
        XCTAssertNotNil(result)
    }

    func testLoadAsyncReturnsCachedImageOnSecondCall() async {
        let path = "/System/Applications"
        let first = await AppIconResolver.loadAsync(atPath: path)
        let second = await AppIconResolver.loadAsync(atPath: path)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
    }

    // MARK: - loadAsync(for:)

    func testLoadAsyncForUnknownDefinitionReturnsNil() async {
        let def = ProcessDefinition(
            id: "ghost",
            displayName: "DefinitelyNotInstalled-\(UUID().uuidString)",
            patterns: ["DefinitelyNotInstalled-\(UUID().uuidString).app"],
            defaultLimitMB: 512
        )
        let result = await AppIconResolver.loadAsync(for: def)
        XCTAssertNil(result)
    }

    func testLoadAsyncForTextEditDefinitionReturnsIcon() async {
        // TextEdit.app is at /System/Applications on every Mac.
        let def = ProcessDefinition(
            id: "textedit",
            displayName: "TextEdit",
            patterns: ["TextEdit.app"],
            defaultLimitMB: 512
        )
        let result = await AppIconResolver.loadAsync(for: def)
        XCTAssertNotNil(result)
    }

    // MARK: - loadAsync(definition:bundlePath:)

    func testLoadAsyncPrefersExplicitBundlePath() async {
        // bundlePath wins over definition when both are supplied.
        let def = ProcessDefinition(id: "ghost", displayName: "Ghost", patterns: [], defaultLimitMB: 1)
        let result = await AppIconResolver.loadAsync(definition: def, bundlePath: "/")
        XCTAssertNotNil(result)
    }

    func testLoadAsyncWithNilDefinitionAndNilPathReturnsNil() async {
        let result = await AppIconResolver.loadAsync(definition: nil, bundlePath: nil)
        XCTAssertNil(result)
    }

    func testLoadAsyncWithNilDefinitionAndValidPathReturnsImage() async {
        let result = await AppIconResolver.loadAsync(definition: nil, bundlePath: "/")
        XCTAssertNotNil(result)
    }

    // MARK: - AppIconCache actor

    func testCacheStoresAndRetrievesImage() async {
        let cache = AppIconCache.shared
        let key = "test-key-\(UUID().uuidString)"
        let image = NSImage(size: NSSize(width: 16, height: 16))
        await cache.set(key, image)
        let hit = await cache.get(key)
        XCTAssertTrue(hit === image)
    }

    func testCacheReturnsNilForUnknownKey() async {
        let hit = await AppIconCache.shared.get("no-such-key-\(UUID().uuidString)")
        XCTAssertNil(hit)
    }

    func testConcurrentLoadsForSamePathAllReturnImages() async {
        // Three concurrent misses may race past the empty cache and each load
        // independently — all must succeed, but object identity isn't guaranteed
        // without in-flight deduplication.
        let path = "/System/Applications"
        async let a = AppIconResolver.loadAsync(atPath: path)
        async let b = AppIconResolver.loadAsync(atPath: path)
        async let c = AppIconResolver.loadAsync(atPath: path)
        let (r1, r2, r3) = await (a, b, c)
        XCTAssertNotNil(r1)
        XCTAssertNotNil(r2)
        XCTAssertNotNil(r3)
    }
}
