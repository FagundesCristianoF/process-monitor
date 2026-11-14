import AppKit
import SwiftUI

/// Blocking "Update required" window for critical releases: floating level,
/// no close button, cannot be dismissed. The app stays blocked until the
/// update is installed or the user quits. Shown again on every launch while
/// outdated, because the updater re-checks right after start.
@MainActor
final class ForcedUpdateWindowController {
    static let shared = ForcedUpdateWindowController()
    private var window: NSWindow?

    private init() {}

    /// Hides the window while Sparkle's own install UI is on screen.
    func hide() {
        window?.orderOut(nil)
    }

    /// Shows the blocking window (idempotent while already visible).
    /// - Parameters:
    ///   - update: the critical update to install.
    ///   - onInstall: starts the install via Sparkle.
    func show(update: AvailableUpdate, onInstall: @escaping () -> Void) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = ForcedUpdateContentView(
            update: update,
            onInstall: onInstall,
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        let hostingView = NSHostingView(rootView: contentView)
        // Fixed size: the content view has a fixed frame, so the window can
        // never stretch to whatever SwiftUI proposes.
        let size = NSSize(width: ForcedUpdateContentView.width, height: ForcedUpdateContentView.height)
        hostingView.frame = NSRect(origin: .zero, size: size)

        // No .closable and no .resizable: the window cannot be dismissed or resized.
        // fullSizeContentView + transparent titlebar lets the content own the look.
        let newWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.title = NSLocalizedString("Update required", comment: "Forced update window title")
        newWindow.titleVisibility = .hidden
        newWindow.titlebarAppearsTransparent = true
        newWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newWindow.standardWindowButton(.zoomButton)?.isHidden = true
        newWindow.isMovableByWindowBackground = true
        newWindow.contentView = hostingView
        newWindow.setContentSize(size)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.makeKeyAndOrderFront(nil)

        // LSUIElement app: activate so the window lands in front.
        NSApp.activate(ignoringOtherApps: true)
        self.window = newWindow
    }
}

/// Content of the blocking window: exactly two actions — install or quit.
private struct ForcedUpdateContentView: View {
    static let width: CGFloat = 380
    static let height: CGFloat = 330

    let update: AvailableUpdate
    let onInstall: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                .padding(.bottom, 14)

            Text("Update required")
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .padding(.bottom, 6)

            Text(String(format: NSLocalizedString("Update available: v%@", comment: "Update banner text. %@ = version"), update.version))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(.orange.opacity(0.14)))
                .padding(.bottom, 14)

            Text("A required update is available. Install it to keep using Process Monitor.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)

            Spacer(minLength: 18)

            HStack(spacing: 10) {
                Button(action: onQuit) {
                    Text("Quit")
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .glassBackground(in: Capsule(), interactive: true)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button(action: onInstall) {
                    Text("Install now")
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .glassBackground(in: Capsule(), tint: .accentColor, interactive: true)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
        }
        .padding(.top, 34)
        .padding(.bottom, 26)
        .frame(width: Self.width, height: Self.height)
    }
}
