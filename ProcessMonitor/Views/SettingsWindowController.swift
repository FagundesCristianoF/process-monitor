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
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 480)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Process Monitor Settings"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        self.window = newWindow
    }
}
