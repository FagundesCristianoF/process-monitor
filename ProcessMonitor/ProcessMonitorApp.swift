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
    @StateObject private var diskMonitorService: DiskMonitorService
    @StateObject private var cleanupStore: CleanupStore

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
        let diskMonitor = DiskMonitorService(
            configStore: config,
            notificationService: notifications
        )
        let cleanup = CleanupStore()
        _configStore = StateObject(wrappedValue: config)
        _launchAtLoginStore = StateObject(wrappedValue: launchAtLogin)
        _notificationService = StateObject(wrappedValue: notifications)
        _monitorService = StateObject(wrappedValue: monitor)
        _diskMonitorService = StateObject(wrappedValue: diskMonitor)
        _cleanupStore = StateObject(wrappedValue: cleanup)
        launchAtLogin.ensureRegistered()
        DispatchQueue.main.async {
            notifications.requestPermissionIfNeeded()
            monitor.startPolling()
            diskMonitor.startPolling()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ProcessListView(
                monitorService: monitorService,
                diskMonitorService: diskMonitorService,
                configStore: configStore,
                launchAtLoginStore: launchAtLoginStore,
                cleanupStore: cleanupStore
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
