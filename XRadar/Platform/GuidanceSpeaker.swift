import AVFoundation

/// French voice for guidance and alerts, like the Android TextToSpeech wrapper: a new phrase cuts
/// the one in progress, and music ducks under the voice instead of stopping (the audio session
/// is shared with the alert sounds). On the main actor explicitly: its delegate protocol is
/// Sendable, which would otherwise make the class nonisolated.
@MainActor
final class GuidanceSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = GuidanceSpeaker.softFrenchVoice()
    private let focus: AudioFocus

    /// A soft French woman's voice: the best installed (premium, then enhanced, then standard),
    /// France first, then other French; the system's French voice otherwise. Novelty and personal
    /// voices are left out.
    private static func softFrenchVoice() -> AVSpeechSynthesisVoice? {
        let women = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.gender == .female
                && !voice.voiceTraits.contains(.isNoveltyVoice)
                && !voice.voiceTraits.contains(.isPersonalVoice)
        }
        for language in ["fr-FR", "fr-CA", "fr-BE", "fr-CH"] {
            if let best = women.filter({ $0.language == language }).max(by: { $0.quality.rawValue < $1.quality.rawValue }) {
                return best
            }
        }
        return AVSpeechSynthesisVoice(language: "fr-FR")
    }

    init(focus: AudioFocus) {
        self.focus = focus
        super.init()
        synthesizer.delegate = self
    }

    /// A phrase is being said: the proximity beeps wait.
    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    /// Speak now, interrupting any instruction in progress.
    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        // Held until this phrase finishes or is cut (each one ends in exactly one of the two).
        focus.acquire()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        // A touch slower than the default, for a calmer voice.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.focus.release() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.focus.release() }
    }
}
