import WidgetKit
import SwiftUI
import Security

// This file belongs to a SEPARATE "Watch Widget Extension" target (not the watch app).
// It is self-contained: its own token read + fetch, so it needs no other files.
// It reads the SAME shared-Keychain JWT, so add the identical keychain-access-groups
// entitlement to this extension target too.

// MARK: - Shared token (same access group as the app)

private enum WidgetKeychain {
    static let accessGroup = "REPLACE_TEAMID.ai.richhealth.shared"
    static let debugToken = ""

    static var token: String? {
        #if DEBUG
        if !debugToken.isEmpty { return debugToken }
        #endif
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.richhealth.auth",
            kSecAttrAccount as String: "jwt",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if !accessGroup.hasPrefix("REPLACE_") {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Minimal fetch: today's steps

private struct Obs: Decodable { let value: Double }
private struct ObsResponse: Decodable { let observations: [Obs] }

private func fetchTodaySteps() async -> Int? {
    guard let token = WidgetKeychain.token else { return nil }
    var comps = URLComponents(url: URL(string: "https://richhealthbackend.vercel.app")!,
                              resolvingAgainstBaseURL: false)!
    comps.path = "/api/observations"
    comps.queryItems = [.init(name: "type", value: "steps"),
                        .init(name: "days", value: "1"),
                        .init(name: "limit", value: "1000")]
    var req = URLRequest(url: comps.url!)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    guard let (data, resp) = try? await URLSession.shared.data(for: req),
          let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
          let decoded = try? JSONDecoder().decode(ObsResponse.self, from: data) else { return nil }
    return Int(decoded.observations.reduce(0) { $0 + $1.value }.rounded())
}

// MARK: - Timeline

struct RHEntry: TimelineEntry {
    let date: Date
    let steps: Int?
}

struct RHProvider: TimelineProvider {
    func placeholder(in context: Context) -> RHEntry { RHEntry(date: Date(), steps: 3200) }

    func getSnapshot(in context: Context, completion: @escaping (RHEntry) -> Void) {
        Task { completion(RHEntry(date: Date(), steps: await fetchTodaySteps())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RHEntry>) -> Void) {
        Task {
            let entry = RHEntry(date: Date(), steps: await fetchTodaySteps())
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

// MARK: - Views (accessory families + Smart Stack)

private let brandTeal = Color(red: 0.0, green: 139.0 / 255.0, blue: 139.0 / 255.0)

struct RHWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RHEntry

    private var stepsText: String { entry.steps.map { "\($0)" } ?? "—" }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(stepsText) steps", systemImage: "figure.walk")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "figure.walk").font(.caption2)
                    Text(stepsText).font(.system(.caption, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
            }
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "figure.walk").foregroundStyle(brandTeal)
                VStack(alignment: .leading, spacing: 1) {
                    Text("RichHealth").font(.caption2).foregroundStyle(.secondary)
                    Text("\(stepsText) steps today")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.7).lineLimit(1)
                }
            }
        default:
            Text("\(stepsText) steps")
        }
    }
}

// MARK: - Widget + bundle

struct RichHealthWidget: Widget {
    let kind = "RichHealthStepsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RHProvider()) { entry in
            RHWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Steps")
        .description("Today's steps from RichHealth.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct RichHealthWidgetBundle: WidgetBundle {
    var body: some Widget { RichHealthWidget() }
}
