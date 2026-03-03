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
        content.title = "Memory Warning"
        content.body = "\(processName) is using \(formatMemory(memoryMB)) "
            + "(limit: \(formatMemory(Double(limitMB)))). "
            + "Consider restarting it."
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
