import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginStore: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?

    init() {
        refresh()
    }

    func ensureRegistered() {
        guard SMAppService.mainApp.status == .notRegistered else {
            refresh()
            return
        }

        setEnabled(true)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }

        refresh()
    }

    func refresh() {
        let enabledMsg = NSLocalizedString("Process Monitor will launch when you log in.", comment: "Launch at login enabled status")
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            if statusMessage == nil {
                statusMessage = enabledMsg
            }
        case .requiresApproval:
            isEnabled = false
            statusMessage = NSLocalizedString("Approve Process Monitor in System Settings > General > Login Items.", comment: "Launch at login requires approval")
        case .notFound, .notRegistered:
            isEnabled = false
            if statusMessage == nil || statusMessage == enabledMsg {
                statusMessage = NSLocalizedString("Enable launch at login to start monitoring automatically.", comment: "Launch at login disabled hint")
            }
        @unknown default:
            isEnabled = false
            statusMessage = NSLocalizedString("Launch at login is unavailable right now.", comment: "Launch at login unavailable")
        }
    }
}
