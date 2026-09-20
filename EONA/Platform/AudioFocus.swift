import AVFoundation

/// The audio session the voice and the alert sounds share: active (the music lowered, not
/// stopped) while one of them plays, and let go a moment after the last one, so a run of beeps
/// does not make the music pump up and down.
final class AudioFocus {
    private var holders = 0
    private var pendingRelease: Task<Void, Never>?

    /// Once per sound or phrase that starts playing.
    func acquire() {
        pendingRelease?.cancel()
        pendingRelease = nil
        holders += 1
        guard holders == 1 else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
    }

    /// Once per sound or phrase that is over.
    func release() {
        guard holders > 0 else { return }
        holders -= 1
        guard holders == 0 else { return }
        pendingRelease = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, holders == 0 else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
