import AppKit
import Foundation
import SwiftUI

/// Shared SwiftUI view for an app icon with consistent placeholder fallback.
struct AppIconBadge: View {
    let definition: ProcessDefinition?
    let bundlePath: String?
    var size: CGFloat = 22
    var dimmed: Bool = false

    init(definition: ProcessDefinition?, bundlePath: String? = nil, size: CGFloat = 22, dimmed: Bool = false) {
        self.definition = definition
        self.bundlePath = bundlePath
        self.size = size
        self.dimmed = dimmed
    }

    var body: some View {
        Group {
            if let nsImage = resolveIcon() {
                Image(nsImage: nsImage)
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
    }

    private func resolveIcon() -> NSImage? {
        if let bundlePath, let img = AppIconResolver.icon(atPath: bundlePath) {
            return img
        }
        if let definition, let img = AppIconResolver.icon(for: definition) {
            return img
        }
        return nil
    }
}

enum AppIconResolver {
    /// Cache icons by resolved path to avoid repeated disk lookups.
    private static var cache: [String: NSImage] = [:]

    /// Try to find the .app bundle for a process definition and return its icon.
    /// Falls back to nil; callers should show a placeholder SF Symbol.
    static func icon(for definition: ProcessDefinition) -> NSImage? {
        if let path = bundlePath(for: definition), let img = icon(atPath: path) {
            return img
        }
        return nil
    }

    /// Resolve an icon directly from a known bundle path.
    static func icon(atPath path: String) -> NSImage? {
        if let cached = cache[path] { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: path)
        cache[path] = img
        return img
    }

    /// Best-effort bundle path lookup using common .app locations and patterns.
    private static func bundlePath(for definition: ProcessDefinition) -> String? {
        // 1. Patterns may contain "<Name>.app" — try /Applications/<pattern> directly.
        for pattern in definition.patterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasSuffix(".app") {
                let appName = (trimmed as NSString).lastPathComponent
                for base in searchPaths {
                    let candidate = (base as NSString).appendingPathComponent(appName)
                    if FileManager.default.fileExists(atPath: candidate) {
                        return candidate
                    }
                }
            }
        }

        // 2. Try /Applications/<DisplayName>.app
        let displayCandidate = "\(definition.displayName).app"
        for base in searchPaths {
            let candidate = (base as NSString).appendingPathComponent(displayCandidate)
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        // 3. NSWorkspace lookup by display name (deprecated but still works on Sonoma/Sequoia).
        if let path = NSWorkspace.shared.fullPath(forApplication: definition.displayName) {
            return path
        }

        return nil
    }

    private static let searchPaths: [String] = [
        "/Applications",
        "/System/Applications",
        NSHomeDirectory() + "/Applications"
    ]
}
