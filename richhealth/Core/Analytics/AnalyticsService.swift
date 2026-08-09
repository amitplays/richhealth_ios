import Foundation

/// First-party, privacy-safe analytics. Fire-and-forget: never blocks the UI, never throws to
/// callers, failures are swallowed. POSTs to /api/analytics/event (auth token injected by APIClient).
///
/// ⚠️ NEVER pass health data or PII in `props`. Only non-sensitive values: counts, plan/tier ids,
/// screen names, model ids. The backend also whitelists event names and strips non-primitive props.
@MainActor
final class Analytics {
    static let shared = Analytics()
    private let api = APIClient()
    private init() {}

    enum Event: String {
        case paywallView       = "paywall_view"
        case subscribeTap      = "subscribe_tap"
        case purchaseSuccess   = "purchase_success"
        case purchaseFailed    = "purchase_failed"
        case restore           = "restore"
        case richieMessageSent = "richie_message_sent"
        case nutricheckRun     = "nutricheck_run"
        case watchSynced       = "watch_synced"
        case reportUploaded    = "report_uploaded"
        case checkinCompleted  = "checkin_completed"
        case screenView        = "screen_view"
        case signupCompleted   = "signup_completed"
        case login             = "login"
        case logout            = "logout"
    }

    private struct EventBody: Encodable {
        let name: String
        let props: [String: String]
        let platform: String
        let appVersion: String
    }

    func track(_ event: Event, _ props: [String: String] = [:]) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let payload = EventBody(name: event.rawValue, props: props, platform: "ios", appVersion: version)
        Task {
            guard let body = try? JSONEncoder().encode(payload) else { return }
            _ = try? await api.send(Endpoint(path: "/api/analytics/event", method: .post, body: body, showsLoader: false))
        }
    }
}
