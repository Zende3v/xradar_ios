import MediaPlayer
import Observation
import UIKit

/// What the music banner shows.
enum MusicPlayback: Equatable {
    /// Access to Music not given; [canAsk] while iOS has never asked.
    case permissionMissing(canAsk: Bool)
    /// Nothing loaded in Music.
    case idle
    /// A track, playing or paused.
    case active(title: String?, artist: String?, artwork: UIImage?, isPlaying: Bool)
}

/// The Music app's player, for the HUD's mini-player. Unlike Android, iOS lets an app read and
/// drive only the system Music player, not Spotify or Deezer (Arthur's choice: Apple Music only).
@MainActor
@Observable
final class MusicPlayer {
    private(set) var playback: MusicPlayback = .permissionMissing(canAsk: true)

    private let player = MPMusicPlayerController.systemMusicPlayer
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var resumeFallback: Task<Void, Never>?

    /// The banner opened: read the player, asking for access to Music the first time.
    func open() {
        guard MPMediaLibrary.authorizationStatus() == .notDetermined else {
            refresh()
            return
        }
        Task {
            _ = await MPMediaLibrary.requestAuthorization()
            refresh()
        }
    }

    /// Reads the player again (the HUD is in front again: it may have changed meanwhile).
    func refresh() {
        let status = MPMediaLibrary.authorizationStatus()
        guard status == .authorized else {
            playback = .permissionMissing(canAsk: status == .notDetermined)
            return
        }
        observe()
        guard let item = player.nowPlayingItem else {
            playback = .idle
            return
        }
        playback = .active(
            title: item.title,
            artist: item.artist,
            artwork: item.artwork?.image(at: CGSize(width: 96, height: 96)),
            isPlaying: player.playbackState == .playing
        )
    }

    /// Play or pause; with nothing queued, Music opens, as Android starts the last music player.
    func playPause() {
        guard MPMediaLibrary.authorizationStatus() == .authorized else { return }
        resumeFallback?.cancel()
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
            resumeFallback = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled, player.playbackState != .playing, let url = URL(string: "music://") else { return }
                _ = await UIApplication.shared.open(url)
            }
        }
        refresh()
    }

    func next() {
        player.skipToNextItem()
        refresh()
    }

    func previous() {
        player.skipToPreviousItem()
        refresh()
    }

    /// The app's page in Réglages, where access to Music is given back.
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func observe() {
        guard observers.isEmpty else { return }
        player.beginGeneratingPlaybackNotifications()
        observers = [
            Self.observe(.MPMusicPlayerControllerNowPlayingItemDidChange, of: player) { [weak self] in self?.refresh() },
            Self.observe(.MPMusicPlayerControllerPlaybackStateDidChange, of: player) { [weak self] in self?.refresh() },
        ]
    }

    /// Formed outside the main actor: the block runs on the main queue and steps back in there.
    nonisolated private static func observe(
        _ name: Notification.Name,
        of player: MPMusicPlayerController,
        _ handler: @escaping @MainActor () -> Void
    ) -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: player, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }
}
