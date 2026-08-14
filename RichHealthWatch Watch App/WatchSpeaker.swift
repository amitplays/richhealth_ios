import Foundation
import AVFoundation

/// Shared text-to-speech for the watch (NutriCheck, Briefing, Ask AI all speak through this).
@MainActor
final class WatchSpeaker {
    static let shared = WatchSpeaker()
    private let synth = AVSpeechSynthesizer()
    private init() {}

    func speak(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: t)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}
