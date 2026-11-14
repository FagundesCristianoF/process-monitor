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
    @StateObject private var updaterService: UpdaterService

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
        let updater = UpdaterService()
        _configStore = StateObject(wrappedValue: config)
        _launchAtLoginStore = StateObject(wrappedValue: launchAtLogin)
        _notificationService = StateObject(wrappedValue: notifications)
        _monitorService = StateObject(wrappedValue: monitor)
        _diskMonitorService = StateObject(wrappedValue: diskMonitor)
        _cleanupStore = StateObject(wrappedValue: cleanup)
        _updaterService = StateObject(wrappedValue: updater)
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
                cleanupStore: cleanupStore,
                updaterService: updaterService
            )
            .frame(width: 420, height: 520)
            .onChange(of: configStore.telemetryEnabled) { enabled in
                Telemetry.setEnabled(enabled)
            }
        } label: {
            MenuBarIconLabel(monitorService: monitorService)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: updaterService.presentation) { presentation in
            switch presentation {
            case .forced(let update):
                // Critical release: block the app and stop both pollers until
                // the update is installed or the user quits.
                ForcedUpdateWindowController.shared.show(update: update) {
                    updaterService.installUpdate()
                }
                monitorService.stopPolling()
                diskMonitorService.stopPolling()
            case .suggest, .none:
                break
            }
        }
        .onChange(of: updaterService.installInProgress) { inProgress in
            // Step aside while Sparkle's install window is up; if the user
            // cancels it and the update is still required, block again.
            if inProgress {
                ForcedUpdateWindowController.shared.hide()
            } else if case .forced(let update) = updaterService.presentation {
                ForcedUpdateWindowController.shared.show(update: update) {
                    updaterService.installUpdate()
                }
            }
        }
    }
}
