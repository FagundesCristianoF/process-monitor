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
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            if statusMessage == nil {
                statusMessage = "Process Monitor will launch when you log in."
            }
        case .requiresApproval:
            isEnabled = false
            statusMessage = "Approve Process Monitor in System Settings > General > Login Items."
        case .notFound, .notRegistered:
            isEnabled = false
            if statusMessage == nil || statusMessage == "Process Monitor will launch when you log in." {
                statusMessage = "Enable launch at login to start monitoring automatically."
            }
        @unknown default:
            isEnabled = false
            statusMessage = "Launch at login is unavailable right now."
        }
    }
}
