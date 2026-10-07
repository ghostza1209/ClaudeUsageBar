import UsageCore
import UserNotifications

/// Shows notifications even while the popover is open (the app is then active, which suppresses them by default).
/// `UNUserNotificationCenter` holds its delegate weakly, so `Usage` keeps this alive.
@MainActor final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// The system prompts only the first time, so calling this on every launch (and when ticket 24's toggle turns on) is safe.
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func post(_ notification: LimitNotification, now: Date) {
        let weekly = notification.window == .sevenDay
        let content = UNMutableNotificationContent()
        content.title = "\(weekly ? "Weekly" : "5-hour") limit at \(Int(notification.percent.rounded()))%"
        content.body =
            "\(notification.level == .critical ? "Critical" : "Warning") threshold reached; "
            + resetText(notification.resetsAt, now: now, weekly: weekly, calendar: .current)
        content.sound = .default
        let id = "\(notification.window.rawValue)-\(notification.level.rawValue)-\(Int(notification.resetsAt.timeIntervalSince1970))"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}
