import AppKit
import SwiftUI

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    private init() {}

    func open(
        configStore: ProcessConfigStore,
        launchAtLoginStore: LaunchAtLoginStore
    ) {
        dismissMenuBarPopover()
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            configStore: configStore,
            launchAtLoginStore: launchAtLoginStore
        )
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 600)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = NSLocalizedString("Process Monitor Settings", comment: "Settings window title")
        newWindow.titlebarAppearsTransparent = false
        newWindow.titleVisibility = .visible
        newWindow.isMovableByWindowBackground = false
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        self.window = newWindow
    }

    /// Close the MenuBarExtra popover window (its class name contains "MenuBarExtraWindow"
    /// or "NSStatusBarWindow"). Called when opening Settings so the popover doesn't
    /// linger alongside the new window.
    private func dismissMenuBarPopover() {
        for win in NSApp.windows where win.isVisible {
            let cls = String(describing: type(of: win))
            if cls.contains("MenuBarExtra") || cls.contains("NSStatusBarWindow") || cls.contains("Popover") {
                win.close()
            }
        }
    }
}
