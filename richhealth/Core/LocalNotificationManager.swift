import UserNotifications
import Foundation

/// Local (on-device) notifications — no push / APNs, so no server, no tokens, no entitlement.
/// This is the seed of the real scheduler (medication reminders, check-ins, daily-brief nudge),
/// mirroring Android's local `CheckInNotificationHelper` (AlarmManager) approach.
///
/// For now it only proves the pipeline end-to-end with a 5-second test notification.
final class LocalNotificationManager: NSObject, UNUserNotificationCenterDelegate {

    static let shared = LocalNotificationManager()
    private override init() { super.init() }

    /// Ask permission (once) and schedule a visible test notification 5 seconds out.
    /// The foreground-presentation delegate below makes it appear even with the app open,
    /// so you can see it fire without backgrounding.
    func fireTest() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { print("[LocalNotif] auth error:", error.localizedDescription) }
            guard granted else { print("[LocalNotif] permission denied"); return }

            let content = UNMutableNotificationContent()
            content.title = "RichHealth"
            content.body = "Local notifications work — this is a test. 🔔"
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let request = UNNotificationRequest(
                identifier: "rh.test." + UUID().uuidString,
                content: content,
                trigger: trigger
            )
            center.add(request) { addError in
                if let addError { print("[LocalNotif] add error:", addError.localizedDescription) }
                else { print("[LocalNotif] test scheduled for +5s") }
            }
        }
    }

    // Show the banner even when the app is in the foreground — needed to see the test immediately.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
