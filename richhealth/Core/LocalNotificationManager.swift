import UserNotifications
import Foundation

/// Local (on-device) notifications — no push / APNs, so no server, no tokens, no entitlement.
/// Mirrors Android's local `CheckInNotificationHelper` (AlarmManager) approach.
///
/// The master on/off reflects the user's `receiveNotifications` intent (mirrored device-locally
/// as `rh.notificationsEnabled` in ProfileViewModel); actual delivery also needs OS permission.
/// Recurring reminders use stable identifiers so re-scheduling replaces rather than duplicates.
final class LocalNotificationManager: NSObject, UNUserNotificationCenterDelegate {

    static let shared = LocalNotificationManager()
    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    // Stable identifiers (replace-by-id on reschedule).
    private static let dailyBriefID = "rh.dailyBrief"
    private static let checkInID    = "rh.checkIn"
    private static func medID(_ id: String, _ index: Int) -> String { "rh.med.\(id).\(index)" }

    // MARK: - Permission

    /// True if we may post notifications: requests on first ask, false if the user denied.
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    // MARK: - Master switch

    /// Turn local notifications on or off. On enable: ensure permission, (re)schedule the
    /// recurring reminders, and post a confirmation. On disable: cancel everything.
    /// Returns the effective state — false if the user denied permission at the OS level.
    @discardableResult
    func setEnabled(_ enabled: Bool, tier: String) async -> Bool {
        guard enabled else {
            cancelAll()
            print("[LocalNotif] disabled → cancelled all pending")
            return false
        }
        guard await requestAuthorizationIfNeeded() else {
            print("[LocalNotif] enable requested but OS permission not granted")
            return false
        }
        cancelAll()
        scheduleDailyBrief()
        scheduleCheckIns(tier: tier)
        fireConfirmation()
        center.getPendingNotificationRequests { reqs in
            print("[LocalNotif] enabled (tier=\(tier)) → \(reqs.count) scheduled: \(reqs.map(\.identifier).joined(separator: ", "))")
        }
        return true
    }

    // MARK: - Schedulers (recurring)

    /// Once-a-day nudge to open the app; the briefing itself refreshes on open.
    func scheduleDailyBrief(hour: Int = 9, minute: Int = 0) {
        var comps = DateComponents(); comps.hour = hour; comps.minute = minute
        let content = UNMutableNotificationContent()
        content.title = "Your health brief is ready"
        content.body  = "Open RichHealth to see what Richie has for you today."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: Self.dailyBriefID, content: content, trigger: trigger),
                   withCompletionHandler: nil)
    }

    /// Medication reminders, one repeating alarm per (medication, reminder time).
    func scheduleMedications(_ meds: [(id: String, name: String, dose: String, times: [DateComponents])]) {
        for med in meds {
            for (i, time) in med.times.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "Time for \(med.name)"
                content.body  = med.dose.isEmpty ? "Tap when taken." : "\(med.dose) — tap when taken."
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
                center.add(UNNotificationRequest(identifier: Self.medID(med.id, i), content: content, trigger: trigger),
                           withCompletionHandler: nil)
            }
        }
    }

    /// Check-in reminders at 9 AM local, cadence by tier — mirrors Android's
    /// CheckInNotificationHelper and the backend check-in period:
    /// ultra → Mon & Thu, pro → Mon, everyone else → 1st of each month.
    func scheduleCheckIns(tier: String) {
        func schedule(_ id: String, _ base: DateComponents) {
            var comps = base; comps.hour = 9; comps.minute = 0
            let content = UNMutableNotificationContent()
            content.title = "Health Check-In Ready 💙"
            content.body  = "Your check-in is ready — it takes about 2 minutes."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger),
                       withCompletionHandler: nil)
        }
        switch tier {
        case "ultra":
            schedule("rh.checkin.mon", DateComponents(weekday: 2)) // Mon
            schedule("rh.checkin.thu", DateComponents(weekday: 5)) // Thu
        case "pro":
            schedule("rh.checkin.mon", DateComponents(weekday: 2))
        default: // free / plus / family / family_member → monthly
            schedule("rh.checkin.monthly", DateComponents(day: 1))
        }
    }

    // MARK: - Confirmation / cancel

    private func fireConfirmation() {
        let content = UNMutableNotificationContent()
        content.title = "Reminders are on"
        content.body  = "We'll remind you about your daily brief, check-ins, and any medications you add."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 4, repeats: false)
        center.add(UNNotificationRequest(identifier: "rh.confirm." + UUID().uuidString, content: content, trigger: trigger),
                   withCompletionHandler: nil)
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Test (kept for now — pipeline probe from the Richie toolbar bell)

    /// Request permission and fire a visible test notification 5 seconds out.
    func fireTest() {
        Task {
            guard await requestAuthorizationIfNeeded() else { print("[LocalNotif] permission denied"); return }
            let content = UNMutableNotificationContent()
            content.title = "RichHealth"
            content.body  = "Local notifications work — this is a test. 🔔"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            center.add(UNNotificationRequest(identifier: "rh.test." + UUID().uuidString, content: content, trigger: trigger),
                       withCompletionHandler: nil)
            print("[LocalNotif] test scheduled for +5s")
        }
    }

    // Show the banner even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
