import Foundation
import UserNotifications

final class NotificationService: ObservableObject {
    /// Default minimum interval between notifications for the same app. Acts as a
    /// per-app push rate limit; configurable via ProcessConfigStore. State is held
    /// in memory only, so it resets when the app restarts.
    static let defaultRateLimit: TimeInterval = 3600 // 1h between notifications per definition

    private var notifiedDefinitionIDs: Set<String> = []
    private var lastNotifiedAt: [String: Date] = [:]
    private var permissionGranted = false
    private let queue = DispatchQueue(label: "NotificationService.state")

    /// Whether the process runs inside a real .app bundle. When false, the
    /// service logs to stdout instead of posting system notifications — both the
    /// production "running headless" path and the test path.
    private let isHosted: Bool
    private let post: (UNNotificationRequest) -> Void
    private let authorize: (@escaping (Bool, Error?) -> Void) -> Void

    init(
        isHosted: Bool = Bundle.main.bundleIdentifier != nil,
        post: @escaping (UNNotificationRequest) -> Void = { req in
            UNUserNotificationCenter.current().add(req) { error in
                if let error {
                    print("Failed to send notification: \(error.localizedDescription)")
                }
            }
        },
        authorize: @escaping (@escaping (Bool, Error?) -> Void) -> Void = { completion in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert], completionHandler: completion)
        }
    ) {
        self.isHosted = isHosted
        self.post = post
        self.authorize = authorize
    }

    func requestPermissionIfNeeded() {
        guard isHosted else { return }
        authorize { [weak self] granted, error in
            if let error {
                print("Notification permission error: \(error.localizedDescription)")
            }
            self?.permissionGranted = granted
        }
    }

    func notifyIfNeeded(
        processName: String,
        memoryMB: Double,
        limitMB: Int,
        definitionID: String,
        rateLimitSeconds: TimeInterval = NotificationService.defaultRateLimit
    ) {
        var shouldSend = false
        let now = Date()
        queue.sync {
            let alreadyNotified = notifiedDefinitionIDs.contains(definitionID)
            let withinCooldown = lastNotifiedAt[definitionID].map {
                now.timeIntervalSince($0) < rateLimitSeconds
            } ?? false
            if !alreadyNotified && !withinCooldown {
                notifiedDefinitionIDs.insert(definitionID)
                lastNotifiedAt[definitionID] = now
                shouldSend = true
            }
        }
        guard shouldSend else { return }
        sendNotification(processName: processName, memoryMB: memoryMB, limitMB: limitMB)
    }

    func resetMemoryNotification(for definitionID: String) {
        queue.sync {
            _ = notifiedDefinitionIDs.remove(definitionID)
        }
    }

    private func sendNotification(processName: String, memoryMB: Double, limitMB: Int) {
        guard isHosted else {
            print(
                "⚠ \(processName) using \(formatMemory(memoryMB)) "
                + "(limit: \(formatMemory(Double(limitMB))))"
            )
            return
        }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Memory Warning", comment: "Notification title for memory warning")
        content.body = Self.memoryBody(processName: processName, memoryMB: memoryMB, limitMB: limitMB)
        let request = UNNotificationRequest(
            identifier: "mem_\(processName)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        post(request)
    }

    func notifyDiskWarning(status: DiskVolumeStatus) {
        guard isHosted else {
            print("⚠ \(status.volume.displayName): \(formatDiskGB(status.freeGB)) free (\(String(format: "%.1f", status.freePercent))%)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Low Disk Space", comment: "Disk warning notification title")
        content.body = Self.diskBody(status: status)
        let request = UNNotificationRequest(
            identifier: "disk_\(status.volume.id)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        post(request)
    }

    func notifyAutoRestart(processName: String, memoryMB: Double, limitMB: Int) {
        guard isHosted else { return }
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Auto-restart triggered", comment: "Auto-restart notification title")
        content.body = Self.autoRestartBody(processName: processName, memoryMB: memoryMB, limitMB: limitMB)
        let request = UNNotificationRequest(
            identifier: "autorestart_\(processName)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        post(request)
    }

    // MARK: - Body builders (pure, testable)

    static func memoryBody(processName: String, memoryMB: Double, limitMB: Int) -> String {
        let bodyFormat = NSLocalizedString(
            "%1$@ is using %2$@ (limit: %3$@). Consider restarting it.",
            comment: "Notification body. %1 = process name, %2 = memory, %3 = limit"
        )
        return String(format: bodyFormat, processName, formatMemory(memoryMB), formatMemory(Double(limitMB)))
    }

    static func diskBody(status: DiskVolumeStatus) -> String {
        let bodyFormat = NSLocalizedString(
            "%1$@ has %2$@ free (%3$@). Consider cleaning up.",
            comment: "Disk warning body. %1=volume name, %2=free space, %3=percent"
        )
        return String(
            format: bodyFormat,
            status.volume.displayName,
            formatDiskGB(status.freeGB),
            String(format: "%.1f%%", status.freePercent)
        )
    }

    static func autoRestartBody(processName: String, memoryMB: Double, limitMB: Int) -> String {
        let bodyFormat = NSLocalizedString(
            "Restarting %1$@ — used %2$@ (limit: %3$@).",
            comment: "Auto-restart body. %1=name, %2=memory, %3=limit"
        )
        return String(format: bodyFormat, processName, formatMemory(memoryMB), formatMemory(Double(limitMB)))
    }
}
