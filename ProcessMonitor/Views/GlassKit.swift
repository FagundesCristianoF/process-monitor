import SwiftUI

/// Frosted-glass style helpers using `.ultraThinMaterial` so the same call
/// sites compile on CI (Xcode 15 / macOS 14 SDK) and on Tahoe.
enum GlassKit {
    /// Card / container corner radius. Inner controls use smaller, concentric radii.
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 7
}

extension View {
    /// Applies a frosted background clipped to `shape`.
    ///
    /// - Parameters:
    ///   - shape: clip shape (use `Capsule()`, `RoundedRectangle`, `Circle()`…).
    ///   - tint: optional tint for prominent / colored surfaces.
    ///   - interactive: reserved for future press/scrub styling; currently unused.
    @ViewBuilder
    func glassBackground<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        self.background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                if let tint {
                    shape.fill(tint.opacity(0.22))
                }
                shape.strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
            }
        }
    }
}

/// Groups glass-styled elements. On all supported macOS versions this is a
/// plain container (no morphing blend).
struct LiquidGlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
    }
}
