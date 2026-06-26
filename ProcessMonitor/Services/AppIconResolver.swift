import AppKit
import Foundation
import SwiftUI

struct AppIconBadge: View {
    let definition: ProcessDefinition?
    let bundlePath: String?
    var size: CGFloat = 22
    var dimmed: Bool = false

    @State private var resolvedIcon: NSImage?

    init(definition: ProcessDefinition?, bundlePath: String? = nil, size: CGFloat = 22, dimmed: Bool = false) {
        self.definition = definition
        self.bundlePath = bundlePath
        self.size = size
        self.dimmed = dimmed
    }

    var body: some View {
        Group {
            if let icon = resolvedIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .opacity(dimmed ? 0.45 : 1.0)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: size * 0.55, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .fill(.tint.opacity(0.12))
                    )
                    .opacity(dimmed ? 0.6 : 1.0)
            }
        }
        .frame(width: size, height: size)
        .task(id: taskId) {
            resolvedIcon = await AppIconResolver.loadAsync(definition: definition, bundlePath: bundlePath)
        }
    }

    private var taskId: String {
        bundlePath ?? definition?.id ?? ""
    }
}

/// Thread-safe icon cache backed by a Swift actor.
actor AppIconCache {
    static let shared = AppIconCache()
    private var store: [String: NSImage] = [:]

    func get(_ key: String) -> NSImage? { store[key] }
    func set(_ key: String, _ image: NSImage) { store[key] = image }
}

/// NSImage isn't Sendable before macOS 14; this wrapper opts out of the check.
/// Safe here because icon images are effectively immutable after creation.
private struct SendableImage: @unchecked Sendable { let image: NSImage }

enum AppIconResolver {
    static func loadAsync(definition: ProcessDefinition?, bundlePath: String?) async -> NSImage? {
        if let bundlePath {
            return await loadAsync(atPath: bundlePath)
        }
        if let definition {
            return await loadAsync(for: definition)
        }
        return nil
    }

    static func loadAsync(for definition: ProcessDefinition) async -> NSImage? {
        guard let path = await resolvedBundlePath(for: definition) else { return nil }
        return await loadAsync(atPath: path)
    }

    /// Returns a cached icon instantly or loads via XPC on a background thread.
    /// The icon is pre-rasterized into an NSBitmapImageRep so SwiftUI layout
    /// never triggers a synchronous XPC call to icon services on the main thread.
    static func loadAsync(atPath path: String) async -> NSImage? {
        let cache = AppIconCache.shared
        if let hit = await cache.get(path) { return hit }
        let box = await Task.detached(priority: .userInitiated) { () -> SendableImage? in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let icon = NSWorkspace.shared.icon(forFile: path)
            return SendableImage(image: icon.preRasterized())
        }.value
        guard let img = box?.image else { return nil }
        await cache.set(path, img)
        return img
    }

    private static func resolvedBundlePath(for definition: ProcessDefinition) async -> String? {
        await Task.detached(priority: .userInitiated) { () -> String? in
            // 1. Patterns containing "<Name>.app"
            for pattern in definition.patterns {
                let trimmed = pattern.trimmingCharacters(in: .whitespaces)
                if trimmed.lowercased().hasSuffix(".app") {
                    let appName = (trimmed as NSString).lastPathComponent
                    for base in searchPaths {
                        let candidate = (base as NSString).appendingPathComponent(appName)
                        if FileManager.default.fileExists(atPath: candidate) { return candidate }
                    }
                }
            }
            // 2. <DisplayName>.app in each search path
            let displayCandidate = "\(definition.displayName).app"
            for base in searchPaths {
                let candidate = (base as NSString).appendingPathComponent(displayCandidate)
                if FileManager.default.fileExists(atPath: candidate) { return candidate }
            }
            return nil
        }.value
    }

    private static let searchPaths: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices",
        NSHomeDirectory() + "/Applications"
    ]
}

private extension NSImage {
    /// Draws the receiver into a fresh NSBitmapImageRep on the calling thread.
    /// Returns the bitmap-backed image so subsequent CGImage access from the
    /// main thread (SwiftUI layout) is a cheap cache hit, never an XPC call.
    func preRasterized() -> NSImage {
        let sz = size
        guard sz.width > 0, sz.height > 0,
              let bmp = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(sz.width),
                pixelsHigh: Int(sz.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              )
        else { return self }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bmp)
        draw(in: NSRect(origin: .zero, size: sz))
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: sz)
        out.addRepresentation(bmp)
        return out
    }
}
