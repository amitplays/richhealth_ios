import Foundation
import Observation

// MARK: - Today glance (richer vitals)

@Observable @MainActor final class TodayGlanceModel {
    struct Metric: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let unit: String
    }

    private(set) var metrics: [Metric] = []
    private(set) var asOf: Date?
    private(set) var source: String?
    private(set) var isLoading = false
    private(set) var errorText: String?

    private let health = HealthService()

    func load() async {
        isLoading = true; errorText = nil
        defer { isLoading = false }
        do {
            // Cumulative day totals
            async let steps = health.total("steps")
            async let energy = health.total("active_energy")
            // Point-in-time latest readings
            async let hr = health.latest("heart_rate")
            async let resting = health.latest("resting_heart_rate")
            async let hrv = health.latest("hrv")
            async let spo2 = health.latest("spo2")
            async let sleep = health.latest("sleep_minutes")
            async let weight = health.latest("weight")

            let stepsR = try await steps
            let energyR = try await energy
            let hrR = try await hr
            let restingR = try await resting
            let hrvR = try await hrv
            let spo2R = try await spo2
            let sleepR = try await sleep
            let weightR = try await weight

            var out: [Metric] = []
            if let s = stepsR { out.append(.init(label: "Steps", value: intStr(s.sum), unit: "today")) }
            if let e = energyR { out.append(.init(label: "Active energy", value: intStr(e.sum), unit: "kcal")) }
            if let v = hrR { out.append(.init(label: "Heart rate", value: intStr(v.value), unit: v.unit ?? "bpm")) }
            if let v = restingR { out.append(.init(label: "Resting HR", value: intStr(v.value), unit: v.unit ?? "bpm")) }
            if let v = hrvR { out.append(.init(label: "HRV", value: intStr(v.value), unit: v.unit ?? "ms")) }
            if let v = spo2R { out.append(.init(label: "Blood oxygen", value: intStr(v.value), unit: v.unit ?? "%")) }
            if let v = sleepR { out.append(.init(label: "Sleep", value: sleepStr(v.value), unit: "")) }
            if let v = weightR { out.append(.init(label: "Weight", value: oneDp(v.value), unit: v.unit ?? "kg")) }

            metrics = out
            let candidates = [hrR, restingR, hrvR, spo2R, sleepR, weightR].compactMap { $0?.effectiveDateTime }
                + [stepsR?.asOf, energyR?.asOf].compactMap { $0 }
            asOf = candidates.max()
            source = stepsR?.source ?? hrR?.sourceName
            if out.isEmpty { errorText = "No health data yet. Open RichHealth on your iPhone to sync." }
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Couldn't load your data."
        }
    }

    private func intStr(_ v: Double) -> String { String(Int(v.rounded())) }
    private func oneDp(_ v: Double) -> String { String(format: "%.1f", v) }
    private func sleepStr(_ minutes: Double) -> String {
        let m = Int(minutes.rounded()); return "\(m / 60)h \(m % 60)m"
    }

    var asOfText: String? {
        guard let asOf else { return nil }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return "as of " + f.localizedString(for: asOf, relativeTo: Date())
    }
}

// MARK: - Daily briefing

@Observable @MainActor final class BriefingModel {
    private(set) var cards: [BriefingCard] = []
    private(set) var isLoading = false
    private(set) var errorText: String?

    private let service = BriefingService()

    func load() async {
        isLoading = true; errorText = nil
        defer { isLoading = false }
        do {
            cards = try await service.fetch().cards
            if cards.isEmpty { errorText = "No briefing yet — check back after your next sync." }
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Couldn't load your briefing."
        }
    }

    func speakAll() {
        guard !cards.isEmpty else { return }
        let text = cards.map { "\($0.title). " + $0.points.joined(separator: ". ") }.joined(separator: ". ")
        WatchSpeaker.shared.speak(text)
    }
}

// MARK: - Ask AI (voice chat)

@Observable @MainActor final class AskAIModel {
    enum Phase { case idle, thinking, answered, error }

    var question: String = ""
    private(set) var phase: Phase = .idle
    private(set) var answer: String = ""
    private(set) var errorText: String = ""

    private let chat = ChatService()
    private var sessionId: String?   // created once, reused for the app's lifetime (respects limits)

    func submit() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        phase = .thinking
        do {
            let sid = try await currentSession()
            let reply = try await chat.ask(q, sessionId: sid)
            answer = reply
            phase = .answered
            WatchSpeaker.shared.speak(reply)
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Couldn't get an answer."
            phase = .error
            WatchSpeaker.shared.speak(errorText)
        }
    }

    private func currentSession() async throws -> String {
        if let sessionId { return sessionId }
        let sid = try await chat.createSession()
        sessionId = sid
        return sid
    }

    func reset() {
        WatchSpeaker.shared.stop()
        question = ""; answer = ""; errorText = ""; phase = .idle
    }
}

// MARK: - NutriCheck (voice)

@Observable @MainActor final class NutriCheckModel {
    enum Phase { case idle, thinking, result, error }

    var foodItem: String = ""
    private(set) var phase: Phase = .idle
    private(set) var verdictLabel: String = ""
    private(set) var reason: String = ""
    private(set) var errorText: String = ""
    private(set) var isPositive: Bool = true

    private let service = NutriCheckService()

    func submit() async {
        let food = foodItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !food.isEmpty else { return }
        phase = .thinking
        do {
            let res = try await service.check(food)
            let rec = (res.recommendation ?? "moderate").lowercased()
            verdictLabel = Self.label(for: rec)
            isPositive = rec == "strong_yes" || rec == "yes"
            reason = res.reason ?? ""
            phase = .result
            WatchSpeaker.shared.speak("\(verdictLabel). \(reason)")
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Couldn't check that."
            phase = .error
            WatchSpeaker.shared.speak(errorText)
        }
    }

    func reset() {
        WatchSpeaker.shared.stop()
        foodItem = ""; verdictLabel = ""; reason = ""; errorText = ""; phase = .idle
    }

    private static func label(for rec: String) -> String {
        switch rec {
        case "strong_yes": return "Great choice"
        case "yes": return "Good to go"
        case "moderate": return "In moderation"
        case "no": return "Better skip it"
        case "strong_no": return "Best avoided"
        default: return "In moderation"
        }
    }
}
