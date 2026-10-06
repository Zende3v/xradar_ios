import AVFAudio
import MediaPlayer
import Observation
import UIKit

/// Sondes publiques Apple : ce que `systemMusicPlayer` et la session audio voient quand une autre
/// app joue (Spotify, YouTube, Deezer…). Diagnostic seulement : valeurs brutes, journal horodaté.
@MainActor
@Observable
final class PublicMediaProbe {
    enum Command: CaseIterable, Identifiable {
        case play, pause, next, previous

        var id: Self { self }

        var title: String {
            switch self {
            case .play: "Musique : lecture (peut lancer Apple Music)"
            case .pause: "Musique : pause"
            case .next: "Musique : suivant"
            case .previous: "Musique : précédent"
            }
        }
    }

    private(set) var report: String?
    private(set) var log: [String] = []
    @ObservationIgnored private let player = MPMusicPlayerController.systemMusicPlayer
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    /// Journal des changements vus pendant que l'écran est ouvert.
    func start() {
        guard observers.isEmpty else { return }
        player.beginGeneratingPlaybackNotifications()
        observers = [
            Self.observe(.MPMusicPlayerControllerNowPlayingItemDidChange, of: player) { [weak self] in self?.event("Titre changé") },
            Self.observe(.MPMusicPlayerControllerPlaybackStateDidChange, of: player) { [weak self] in self?.event("État changé") },
            Self.observe(AVAudioSession.silenceSecondaryAudioHintNotification, of: nil) { [weak self] in self?.event("Autre audio démarré ou arrêté") },
        ]
    }

    /// Notifications du lecteur gardées : le mini-player les utilise aussi.
    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    func read() async {
        if MPMediaLibrary.authorizationStatus() == .notDetermined {
            _ = await MPMediaLibrary.requestAuthorization()
        }
        report = snapshot()
    }

    func send(_ command: Command) {
        switch command {
        case .play: player.play()
        case .pause: player.pause()
        case .next: player.skipToNextItem()
        case .previous: player.skipToPreviousItem()
        }
        event("Commande \(command.title)")
    }

    var copyText: String {
        ([report ?? "Aucune lecture"] + log).joined(separator: "\n")
    }

    private func snapshot() -> String {
        let session = AVAudioSession.sharedInstance()
        let status: String = switch MPMediaLibrary.authorizationStatus() {
        case .authorized: "autorisé"
        case .denied: "refusé"
        case .restricted: "restreint"
        case .notDetermined: "non demandé"
        @unknown default: "inconnu"
        }
        let own = MPNowPlayingInfoCenter.default().nowPlayingInfo
        let outputs = session.currentRoute.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
        return [
            "Autorisation Musique : \(status)",
            "systemMusicPlayer : \(stateText) · position \(positionText) · index \(player.indexOfNowPlayingItem)",
            itemText,
            "NowPlayingInfoCenter (EONA) : \(own.map { "\($0.count) clés" } ?? "nil")",
            "Autre audio actif : \(session.isOtherAudioPlaying ? "oui" : "non") · audio secondaire à couper : \(session.secondaryAudioShouldBeSilencedHint ? "oui" : "non")",
            "Sortie audio : \(outputs.isEmpty ? "aucune" : outputs)",
        ].joined(separator: "\n")
    }

    private var stateText: String {
        switch player.playbackState {
        case .stopped: "arrêté"
        case .playing: "lecture"
        case .paused: "pause"
        case .interrupted: "interrompu"
        case .seekingForward: "avance"
        case .seekingBackward: "recul"
        @unknown default: "inconnu"
        }
    }

    private var positionText: String {
        let time = player.currentPlaybackTime
        return time.isFinite ? "\(Int(time)) s" : "inconnue"
    }

    private var itemText: String {
        guard let item = player.nowPlayingItem else { return "nowPlayingItem : nil" }
        let artwork = item.artwork.map { "\(Int($0.bounds.width))×\(Int($0.bounds.height))" } ?? "aucune"
        return "nowPlayingItem : \(item.title ?? "sans titre") · \(item.artist ?? "sans artiste") · \(item.albumTitle ?? "sans album") · \(Int(item.playbackDuration)) s · pochette \(artwork)"
    }

    private func event(_ label: String) {
        let time = Date.now.formatted(date: .omitted, time: .standard)
        let title = player.nowPlayingItem?.title ?? "nil"
        let other = AVAudioSession.sharedInstance().isOtherAudioPlaying ? "oui" : "non"
        log.insert("\(time) \(label) → \(stateText) · titre \(title) · autre audio \(other)", at: 0)
        if log.count > 20 { log.removeLast() }
    }

    /// Formé hors acteur principal : le bloc tourne sur la file principale et y revient.
    nonisolated private static func observe(
        _ name: Notification.Name,
        of player: MPMusicPlayerController?,
        _ handler: @escaping @MainActor () -> Void
    ) -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: player, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }
}
