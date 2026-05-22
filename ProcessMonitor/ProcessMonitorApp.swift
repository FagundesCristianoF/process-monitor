import SwiftUI

private struct MenuBarIconLabel: View {
    @ObservedObject var monitorService: ProcessMonitorService

    private var hasWarning: Bool {
        hasOverLimitProcess(monitorService.processes)
    }

    var body: some View {
        Image(systemName: hasWarning
            ? "exclamationmark.triangle.fill"
            : "cpu"
        )
        .symbolRenderingMode(.palette)
        .foregroundStyle(hasWarning ? .orange : .primary)
    }
}

@main
struct ProcessMonitorApp: App {
    @StateObject private var configStore: ProcessConfigStore
    @StateObject private var launchAtLoginStore: LaunchAtLoginStore
    @StateObject private var notificationService: NotificationService
    @StateObject private var monitorService: ProcessMonitorService

    init() {
        let config = ProcessConfigStore()
        Telemetry.start(enabled: config.telemetryEnabled)
        Telemetry.breadcrumb("App launched", category: "lifecycle")
        let launchAtLogin = LaunchAtLoginStore()
        let notifications = NotificationService()
        let monitor = ProcessMonitorService(
            configStore: config,
            notificationService: notifications
        )
        _configStore = StateObject(wrappedValue: config)
        _launchAtLoginStore = StateObject(wrappedValue: launchAtLogin)
        _notificationService = StateObject(wrappedValue: notifications)
        _monitorService = StateObject(wrappedValue: monitor)
        launchAtLogin.ensureRegistered()
        notifications.requestPermissionIfNeeded()
        DispatchQueue.main.async {
            monitor.startPolling()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ProcessListView(
                monitorService: monitorService,
                configStore: configStore,
                launchAtLoginStore: launchAtLoginStore
            )
            .frame(width: 420, height: 520)
            .onChange(of: configStore.telemetryEnabled) { enabled in
                Telemetry.setEnabled(enabled)
            }
        } label: {
            MenuBarIconLabel(monitorService: monitorService)
        }
        .menuBarExtraStyle(.window)
    }
}
