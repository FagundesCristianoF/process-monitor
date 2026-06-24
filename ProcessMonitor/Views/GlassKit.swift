import SwiftUI

/// Liquid Glass helpers.
///
/// On macOS 26 (Tahoe) and later these use the real `glassEffect` API. On
/// earlier systems they fall back to an `.ultraThinMaterial` + tint + hairline
/// approximation so the same call sites compile and look reasonable everywhere.
enum GlassKit {
    /// Card / container corner radius. Inner controls use smaller, concentric radii.
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 7
}

extension View {
    /// Applies a Liquid Glass background clipped to `shape`.
    ///
    /// - Parameters:
    ///   - shape: clip shape (use `Capsule()`, `RoundedRectangle`, `Circle()`…).
    ///   - tint: optional tint for prominent / colored surfaces.
    ///   - interactive: enables the interactive glass response (press/scrub).
    @ViewBuilder
    func glassBackground<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                Self.makeGlass(tint: tint, interactive: interactive),
                in: shape
            )
        } else {
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

    @available(macOS 26.0, *)
    private static func makeGlass(tint: Color?, interactive: Bool) -> Glass {
        var glass: Glass = .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// Groups several glass elements so they blend and morph together. No-op
/// container on macOS < 26.
struct LiquidGlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}
