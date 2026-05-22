import Foundation
import UserNotifications

final class NotificationService: ObservableObject {
    private var lastNotificationTime: [String: Date] = [:]
    private let cooldown: TimeInterval = 300 // 5 minutes
    private var permissionGranted = false

    init() {}

    func requestPermissionIfNeeded() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { [weak self] granted, error in
            if let error {
                print("Notification permission error: \(error.localizedDescription)")
            }
            self?.permissionGranted = granted
        }
    }

    func notifyIfNeeded(processName: String, memoryMB: Double, limitMB: Int) {
        let now = Date()
        if let last = lastNotificationTime[processName],
           now.timeIntervalSince(last) < cooldown {
            return
        }

        lastNotificationTime[processName] = now
        sendNotification(processName: processName, memoryMB: memoryMB, limitMB: limitMB)
    }

    private func sendNotification(processName: String, memoryMB: Double, limitMB: Int) {
        guard Bundle.main.bundleIdentifier != nil else {
            print(
                "⚠ \(processName) using \(formatMemory(memoryMB)) "
                + "(limit: \(formatMemory(Double(limitMB))))"
            )
            return
        }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Memory Warning", comment: "Notification title for memory warning")
        let bodyFormat = NSLocalizedString(
            "%1$@ is using %2$@ (limit: %3$@). Consider restarting it.",
            comment: "Notification body. %1 = process name, %2 = memory, %3 = limit"
        )
        content.body = String(
            format: bodyFormat,
            processName,
            formatMemory(memoryMB),
            formatMemory(Double(limitMB))
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "mem_\(processName)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
}
