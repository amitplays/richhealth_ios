import Foundation
import Observation
import AVFoundation

// MARK: - Today glance

/// Loads the day's key vitals from the backend (data the iPhone app synced from Apple Health).
/// "As of" is shown because freshness = the last iOS → backend sync, not a live wrist reading.
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
            async let steps = health.total("steps")
            async let energy = health.total("active_energy")
            async let hr = health.latest("heart_rate")

            let (stepsSum, stepsAsOf, stepsSrc) = try await steps
            let (energySum, _, _) = try await energy
            let heart = try await hr

            var out: [Metric] = []
            out.append(.init(label: "Steps", value: fmt(stepsSum), unit: "today"))
            out.append(.init(label: "Active energy", value: fmt(energySum), unit: "kcal"))
            if let heart { out.append(.init(label: "Heart rate", value: fmt(heart.value), unit: heart.unit ?? "bpm")) }

            metrics = out
            asOf = heart?.effectiveDateTime ?? stepsAsOf
            source = stepsSrc
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Couldn't load your data."
        }
    }

    private func fmt(_ v: Double) -> String {
        v >= 100 ? String(Int(v.rounded())) : String(format: "%.0f", v)
    }

    var asOfText: String? {
        guard let asOf else { return nil }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return "as of " + f.localizedString(for: asOf, relativeTo: Date())
    }
}

// MARK: - NutriCheck voice

/// Voice in (system Dictation via the text field) → backend NutriCheck → voice out (AVSpeechSynthesizer).
@Observable @MainActor final class NutriCheckModel {
    enum Phase { case idle, thinking, result, error }

    var foodItem: String = ""
    private(set) var phase: Phase = .idle
    private(set) var verdictLabel: String = ""
    private(set) var reason: String = ""
    private(set) var errorText: String = ""
    /// true for positive verdicts → tint teal; false → neutral. No other colors (house rule).
    private(set) var isPositive: Bool = true

    private let service = NutriCheckService()
    private let speaker = AVSpeechSynthesizer()

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
            speak("\(verdictLabel). \(reason)")
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Couldn't check that."
            phase = .error
            speak(errorText)
        }
    }

    func reset() {
        speaker.stopSpeaking(at: .immediate)
        foodItem = ""; verdictLabel = ""; reason = ""; errorText = ""; phase = .idle
    }

    private func speak(_ text: String) {
        guard !text.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        speaker.speak(u)
    }

    /// Neutral, brand-consistent phrasing — no red/green language, matching "only our app color".
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
