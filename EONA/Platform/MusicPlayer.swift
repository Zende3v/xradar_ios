import MediaPlayer
import Observation
import UIKit

/// What the music banner shows.
enum MusicPlayback: Equatable {
    /// Access to Music not given; [canAsk] while iOS has never asked.
    case permissionMissing(canAsk: Bool)
    /// Nothing loaded.
    case idle
    /// A track, playing or paused.
    case active(title: String?, artist: String?, artwork: UIImage?, isPlaying: Bool)
    /// Spotify chosen, not connected; [message] says why when a connection just failed.
    case spotifySignIn(message: String?)
    /// Spotify answers, but will not let this account in (not on the test list, and the like).
    case unavailable(String)
}

/// Where the music comes from: the Music app, or the driver's Spotify account.
enum MusicSource: String, CaseIterable {
    case appleMusic
    case spotify

    var name: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        }
    }
}

/// The HUD's mini-player. Two sources: the system Music player, read and driven on the phone,
/// and Spotify, read and driven through Spotify's Web API once the driver connected their
/// account. The chosen source is remembered on the phone.
@MainActor
@Observable
final class MusicPlayer {
    private(set) var source: MusicSource
    private(set) var applePlayback: MusicPlayback = .permissionMissing(canAsk: true)
    /// Spotify's side, whatever the source: it keeps its own state.
    let spotify: SpotifyRemote

    /// What the banner shows, from the chosen source.
    var playback: MusicPlayback {
        source == .spotify ? spotify.playback : applePlayback
    }

    /// Spotify is offered only when this build carries its client id.
    var spotifyAvailable: Bool { SpotifyAuth.isAvailable }

    private let player = MPMusicPlayerController.systemMusicPlayer
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var resumeFallback: Task<Void, Never>?
    /// The banner is on screen: Spotify is only asked while it is.
    @ObservationIgnored private var bannerOpen = false

    init(spotify: SpotifyRemote, defaults: UserDefaults = .standard) {
        self.spotify = spotify
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.sourceKey).flatMap(MusicSource.init(rawValue:)) ?? .appleMusic
        source = saved == .spotify && !SpotifyAuth.isAvailable ? .appleMusic : saved
    }

    /// Chooses where the music comes from, and remembers it.
    func choose(_ next: MusicSource) {
        guard next != source, next != .spotify || spotifyAvailable else { return }
        source = next
        defaults.set(next.rawValue, forKey: Self.sourceKey)
        if bannerOpen {
            if next == .spotify {
                spotify.start()
            } else {
                spotify.stop()
                refresh()
            }
        }
    }

    /// The banner opened: read the player, asking for access to Music the first time.
    func open() {
        bannerOpen = true
        if source == .spotify {
            spotify.start()
            return
        }
        guard MPMediaLibrary.authorizationStatus() == .notDetermined else {
            refresh()
            return
        }
        Task {
            _ = await MPMediaLibrary.requestAuthorization()
            refresh()
        }
    }

    /// The banner closed: Spotify is left alone until it opens again.
    func close() {
        bannerOpen = false
        spotify.stop()
    }

    /// Reads the player again (the HUD is in front again: it may have changed meanwhile).
    func refresh() {
        if source == .spotify {
            if bannerOpen { Task { await spotify.refresh() } }
            return
        }
        let status = MPMediaLibrary.authorizationStatus()
        guard status == .authorized else {
            applePlayback = .permissionMissing(canAsk: status == .notDetermined)
            return
        }
        observe()
        guard let item = player.nowPlayingItem else {
            applePlayback = .idle
            return
        }
        applePlayback = .active(
            title: item.title,
            artist: item.artist,
            artwork: item.artwork?.image(at: CGSize(width: 96, height: 96)),
            isPlaying: player.playbackState == .playing
        )
    }

    /// Play or pause; with nothing queued, Music (or Spotify) opens, as Android starts the last
    /// music player.
    func playPause() {
        if source == .spotify {
            Task { await spotify.playPause() }
            return
        }
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
        if source == .spotify {
            Task { await spotify.next() }
            return
        }
        player.skipToNextItem()
        refresh()
    }

    func previous() {
        if source == .spotify {
            Task { await spotify.previous() }
            return
        }
        player.skipToPreviousItem()
        refresh()
    }

    /// The app's page in Réglages, where access to Music is given back.
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private static let sourceKey = "xr_music.source"

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
