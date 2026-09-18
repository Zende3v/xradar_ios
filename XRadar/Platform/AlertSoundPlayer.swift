import AVFoundation
import UIKit

/// The alert sounds, radar-detector style, played over the music (lowered meanwhile), with a
/// haptic tap when the driver wants vibration.
final class AlertSoundPlayer: NSObject, AVAudioPlayerDelegate {
    enum Sound: String, CaseIterable {
        /// A speed-enforcement alert shows up: the detector's K/Ka band chirps.
        case detector = "alert_detector"
        /// One proximity beep; they come faster as the radar nears.
        case beep = "alert_beep"
        /// Right at the radar: the laser burst.
        case laser = "alert_laser"
        /// A road hazard shows up: a two-note chime.
        case hazard = "alert_hazard"
        /// Over the speed limit: a rising "bi-bip", lower and buzzier than the proximity beep.
        case overspeed = "alert_overspeed"
    }

    private let focus: AudioFocus
    private var players: [Sound: AVAudioPlayer] = [:]
    /// Players that took the audio focus and still hold it.
    private var holding: Set<ObjectIdentifier> = []
    private let warning = UINotificationFeedbackGenerator()
    private let tap = UIImpactFeedbackGenerator(style: .rigid)

    init(focus: AudioFocus) {
        self.focus = focus
        super.init()
        for sound in Sound.allCases {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url)
            else { continue }
            player.delegate = self
            player.prepareToPlay()
            players[sound] = player
        }
    }

    /// [volume] (0...1): "Volume alertes".
    func play(_ sound: Sound, vibrate: Bool, volume: Double) {
        guard let player = players[sound] else { return }
        player.volume = Float(min(max(volume, 0), 1))
        let id = ObjectIdentifier(player)
        if !holding.contains(id) {
            holding.insert(id)
            focus.acquire()
        }
        player.currentTime = 0
        player.play()
        guard vibrate else { return }
        if sound == .beep {
            tap.impactOccurred()
        } else {
            warning.notificationOccurred(.warning)
        }
    }

    private func finished(_ id: ObjectIdentifier) {
        guard holding.remove(id) != nil else { return }
        focus.release()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.finished(id) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.finished(id) }
    }
}
