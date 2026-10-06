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
    /// Lecteur global : commandes disponibles même si iOS masque métadonnées ou état.
    case systemControls(title: String?, artist: String?, artwork: UIImage?, isPlaying: Bool?)
    /// Spotify chosen, not connected; [message] says why when a connection just failed.
    case spotifySignIn(message: String?)
    /// Spotify answers, but will not let this account in (not on the test list, and the like).
    case unavailable(String)
}

/// Apple Music, Spotify ou lecteur actif dans variante IPA interne.
enum MusicSource: String, CaseIterable {
    case appleMusic
    case spotify
    case system

    var name: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .system: "Lecteur système"
        }
    }
}

/// Mini-player : sources indépendantes, choix local conservé. Lecteur global proposé seulement dans IPA interne.
@MainActor
@Observable
final class MusicPlayer {
    private(set) var source: MusicSource
    private(set) var applePlayback: MusicPlayback = .permissionMissing(canAsk: true)
    /// Spotify's side, whatever the source: it keeps its own state.
    let spotify: SpotifyRemote
    let system = SystemMediaRemote()

    /// What the banner shows, from the chosen source.
    var playback: MusicPlayback {
        switch source {
        case .appleMusic: applePlayback
        case .spotify: spotify.playback
        case .system: system.playback
        }
    }

    /// Spotify is offered only when this build carries its client id.
    var spotifyAvailable: Bool { SpotifyAuth.isAvailable }
    var systemAvailable: Bool { system.available }
    var availableSources: [MusicSource] {
        [.appleMusic] + (spotifyAvailable ? [.spotify] : []) + (systemAvailable ? [.system] : [])
    }

    private let player = MPMusicPlayerController.systemMusicPlayer
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var resumeFallback: Task<Void, Never>?
    /// The banner is on screen: Spotify is only asked while it is.
    @ObservationIgnored private var bannerOpen = false
    @ObservationIgnored private var foreground = true

    init(spotify: SpotifyRemote, defaults: UserDefaults = .standard) {
        self.spotify = spotify
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.sourceKey).flatMap(MusicSource.init(rawValue:)) ?? .appleMusic
        if saved == .spotify && !SpotifyAuth.isAvailable || saved == .system && !EONASystemMedia.isEnabled() {
            source = .appleMusic
        } else {
            source = saved
        }
    }

    /// Chooses where the music comes from, and remembers it.
    func choose(_ next: MusicSource) {
        guard next != source, availableSources.contains(next) else { return }
        resumeFallback?.cancel()
        resumeFallback = nil
        spotify.stop()
        system.stop()
        source = next
        defaults.set(next.rawValue, forKey: Self.sourceKey)
        if bannerOpen && foreground { open() }
    }

    /// The banner opened: read the player, asking for access to Music the first time.
    func open() {
        bannerOpen = true
        guard foreground else { return }
        if source == .system {
            system.start()
            return
        }
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
        system.stop()
        resumeFallback?.cancel()
        resumeFallback = nil
    }

    /// Polling suspendu hors écran et en arrière-plan ; reprise conserve source choisie.
    func setForeground(_ active: Bool) {
        guard active != foreground else { return }
        foreground = active
        if active {
            if bannerOpen { open() }
        } else {
            spotify.stop()
            system.stop()
            resumeFallback?.cancel()
            resumeFallback = nil
        }
    }

    func retrySystem() {
        guard source == .system, bannerOpen, foreground else { return }
        system.retry()
    }

    /// Reads the player again (the HUD is in front again: it may have changed meanwhile).
    func refresh() {
        if source == .system {
            if bannerOpen && foreground {
                system.start()
                system.refresh()
            }
            return
        }
        if source == .spotify {
            if bannerOpen && foreground { Task { await spotify.refresh() } }
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
        if source == .system {
            system.playPause()
            return
        }
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
        if source == .system {
            system.next()
            return
        }
        if source == .spotify {
            Task { await spotify.next() }
            return
        }
        player.skipToNextItem()
        refresh()
    }

    func previous() {
        if source == .system {
            system.previous()
            return
        }
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
