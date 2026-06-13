import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginStore: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?

    private let statusProvider: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void

    init(
        statusProvider: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
        register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }
    ) {
        self.statusProvider = statusProvider
        self.register = register
        self.unregister = unregister
        refresh()
    }

    func ensureRegistered() {
        guard statusProvider() == .notRegistered else {
            refresh()
            return
        }

        setEnabled(true)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try register()
            } else {
                try unregister()
            }
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }

        refresh()
    }

    func refresh() {
        let resolved = Self.resolve(status: statusProvider(), existingMessage: statusMessage)
        isEnabled = resolved.isEnabled
        statusMessage = resolved.statusMessage
    }

    struct Resolved: Equatable {
        let isEnabled: Bool
        let statusMessage: String?
    }

    /// Pure mapping from login-item status to UI state. Extracted so every
    /// status branch is unit-testable without the SMAppService singleton.
    static func resolve(status: SMAppService.Status, existingMessage: String?) -> Resolved {
        let enabledMsg = NSLocalizedString("Process Monitor will launch when you log in.", comment: "Launch at login enabled status")
        switch status {
        case .enabled:
            return Resolved(isEnabled: true, statusMessage: existingMessage ?? enabledMsg)
        case .requiresApproval:
            return Resolved(
                isEnabled: false,
                statusMessage: NSLocalizedString("Approve Process Monitor in System Settings > General > Login Items.", comment: "Launch at login requires approval")
            )
        case .notFound, .notRegistered:
            if existingMessage == nil || existingMessage == enabledMsg {
                return Resolved(
                    isEnabled: false,
                    statusMessage: NSLocalizedString("Enable launch at login to start monitoring automatically.", comment: "Launch at login disabled hint")
                )
            }
            return Resolved(isEnabled: false, statusMessage: existingMessage)
        @unknown default:
            return Resolved(
                isEnabled: false,
                statusMessage: NSLocalizedString("Launch at login is unavailable right now.", comment: "Launch at login unavailable")
            )
        }
    }
}
