import AVFoundation

/// French voice for guidance and alerts, like the Android TextToSpeech wrapper: a new phrase cuts
/// the one in progress, and music ducks under the voice instead of stopping (the audio session
/// is shared with the alert sounds).
final class GuidanceSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "fr-FR")
    private let focus: AudioFocus

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
