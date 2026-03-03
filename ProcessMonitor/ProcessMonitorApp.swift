import SwiftUI

@main
struct ProcessMonitorApp: App {
    @StateObject private var configStore: ProcessConfigStore
    @StateObject private var launchAtLoginStore: LaunchAtLoginStore
    @StateObject private var notificationService: NotificationService
    @StateObject private var monitorService: ProcessMonitorService

    init() {
        let config = ProcessConfigStore()
        let launchAtLogin = LaunchAtLoginStore()
        let notifications = NotificationService()
        _configStore = StateObject(wrappedValue: config)
        _launchAtLoginStore = StateObject(wrappedValue: launchAtLogin)
        _notificationService = StateObject(wrappedValue: notifications)
        _monitorService = StateObject(
            wrappedValue: ProcessMonitorService(
                configStore: config,
                notificationService: notifications
            )
        )
        launchAtLogin.ensureRegistered()
        notifications.requestPermissionIfNeeded()
    }

    private var hasWarning: Bool {
        monitorService.processes.contains { $0.status == .overLimit }
    }

    var body: some Scene {
        MenuBarExtra {
            ProcessListView(
                monitorService: monitorService,
                configStore: configStore,
                launchAtLoginStore: launchAtLoginStore
            )
            .frame(width: 420, height: 520)
        } label: {
            Image(systemName: hasWarning
                ? "exclamationmark.triangle.fill"
                : "cpu"
            )
            .symbolRenderingMode(.palette)
            .foregroundStyle(hasWarning ? .orange : .primary)
        }
        .menuBarExtraStyle(.window)
    }
}
