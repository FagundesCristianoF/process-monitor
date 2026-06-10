import AppKit
import SwiftUI

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    private init() {}

    func open(
        configStore: ProcessConfigStore,
        launchAtLoginStore: LaunchAtLoginStore,
        diskMonitorService: DiskMonitorService
    ) {
        dismissMenuBarPopover()
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            configStore: configStore,
            launchAtLoginStore: launchAtLoginStore,
            diskMonitorService: diskMonitorService
        )
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 700, height: 540)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = NSLocalizedString("Process Monitor Settings", comment: "Settings window title")
        newWindow.titlebarAppearsTransparent = false
        newWindow.titleVisibility = .visible
        newWindow.isMovableByWindowBackground = false
        newWindow.contentView = hostingView
        newWindow.minSize = NSSize(width: 680, height: 460)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .normal
        newWindow.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        self.window = newWindow
    }

    /// Dismiss the MenuBarExtra popover by ordering its window out — NOT
    /// closing it. Closing the window can break the underlying NSStatusItem
    /// so subsequent menu bar clicks fail to show the popover.
    /// We only target known popover-style classes; the status item's own
    /// NSStatusBarWindow is left alone.
    private func dismissMenuBarPopover() {
        for win in NSApp.windows where win.isVisible {
            let cls = String(describing: type(of: win))
            // Only popover-style classes; NEVER touch NSStatusBarWindow
            // because that hosts the status item and closing it disables clicks.
            if cls.contains("MenuBarExtraWindow") || cls.contains("NSPopover") {
                win.orderOut(nil)
            }
        }
    }
}
