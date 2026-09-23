import Foundation
import Observation
import UIKit

/// Spotify in the HUD's mini-player, through Spotify's Web API: what plays on the driver's
/// account, and play, pause, next, previous. The music itself plays in the Spotify app (or on
/// whatever device the account uses); EONA only reads it and drives it.
///
/// Driving the playback needs Spotify Premium, as Spotify decides. Reading works for everyone.
@MainActor
@Observable
final class SpotifyRemote {
    private(set) var playback: MusicPlayback = .spotifySignIn(message: nil)
    /// True while the sign-in page is open or a command is on its way.
    private(set) var busy = false
    /// A refusal from Spotify, a few seconds under the track (Premium needed, no device…).
    private(set) var notice: String?

    @ObservationIgnored private let auth: SpotifyAuth
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var artworkURL: URL?
    @ObservationIgnored private var artwork: UIImage?

    init(auth: SpotifyAuth) {
        self.auth = auth
        if auth.isSignedIn { playback = .idle }
    }

    var isSignedIn: Bool { auth.isSignedIn }

    func signIn() async {
        busy = true
        let problem = await auth.signIn()
        busy = false
        if auth.isSignedIn {
            playback = .idle
            await refresh()
            startPolling()
        } else {
            playback = .spotifySignIn(message: problem)
        }
    }

    func signOut() {
        stopPolling()
        auth.signOut()
        artwork = nil
        artworkURL = nil
        playback = .spotifySignIn(message: nil)
    }

    /// The banner is open with Spotify: the state is read now, then every few seconds.
    func start() {
        guard auth.isSignedIn else {
            if case .spotifySignIn = playback {} else { playback = .spotifySignIn(message: nil) }
            return
        }
        startPolling()
    }

    /// The banner is closed, or the source changed: nothing more is asked of Spotify.
    func stop() {
        stopPolling()
    }

    /// Reads what plays now.
    func refresh() async {
        guard let token = await auth.accessToken() else {
            playback = .spotifySignIn(message: auth.isSignedIn ? nil : "Reconnecte Spotify pour reprendre.")
            stopPolling()
            return
        }
        guard let (status, json) = await Self.call("GET", "me/player", token: token) else { return }
        switch status {
        case 200:
            await show(json)
        case 204:
            // Signed in, nothing playing on any device of the account.
            playback = .idle
        case 401:
            playback = .spotifySignIn(message: "Reconnecte Spotify pour reprendre.")
        case 403:
            playback = .unavailable(Self.refusal(json))
        default:
            break
        }
    }

    func playPause() async {
        let playing = isPlaying
        await command("PUT", playing ? "me/player/pause" : "me/player/play", startsSpotify: !playing)
    }

    private var isPlaying: Bool {
        guard case .active(_, _, _, let playing) = playback else { return false }
        return playing
    }

    func next() async {
        await command("POST", "me/player/next", startsSpotify: false)
    }

    func previous() async {
        await command("POST", "me/player/previous", startsSpotify: false)
    }

    // MARK: Internals

    /// Sends one command, then reads the state again — Spotify takes a moment to settle.
    private func command(_ method: String, _ path: String, startsSpotify: Bool) async {
        guard let token = await auth.accessToken() else {
            playback = .spotifySignIn(message: "Reconnecte Spotify pour reprendre.")
            return
        }
        busy = true
        let answer = await Self.call(method, path, token: token)
        busy = false
        switch answer?.status {
        case 404 where startsSpotify:
            // No device awake: Spotify opens, and plays once there.
            openSpotify()
        case 404:
            note("Aucun appareil Spotify actif. Lance la lecture dans Spotify.")
        case 403:
            note(Self.refusal(answer?.json))
        default:
            break
        }
        try? await Task.sleep(for: .milliseconds(350))
        await refresh()
    }

    private func show(_ json: [String: Any]?) async {
        guard let json, let item = json["item"] as? [String: Any] else {
            playback = .idle
            return
        }
        let title = item["name"] as? String
        // A song has artists; an episode has its show.
        let artists = (item["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        let show = (item["show"] as? [String: Any])?["name"] as? String
        let subtitle = artists.map { $0.joined(separator: ", ") } ?? show
        let images = ((item["album"] as? [String: Any])?["images"] as? [[String: Any]])
            ?? (item["images"] as? [[String: Any]])
            ?? []
        // The smallest picture that still fills the 48-point square.
        let picked = images
            .compactMap { image -> (URL, Int)? in
                guard let text = image["url"] as? String, let url = URL(string: text) else { return nil }
                return (url, (image["width"] as? NSNumber)?.intValue ?? 640)
            }
            .sorted { $0.1 < $1.1 }
            .first { $0.1 >= 96 }?.0
        if let picked, picked != artworkURL {
            artworkURL = picked
            artwork = await Self.image(picked)
        } else if picked == nil {
            // No picture for this one: the note, not the last cover.
            artworkURL = nil
            artwork = nil
        }
        playback = .active(
            title: title,
            artist: subtitle,
            artwork: artwork,
            isPlaying: json["is_playing"] as? Bool ?? false
        )
    }

    private func startPolling() {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(Self.pollSeconds))
            }
        }
    }

    private func stopPolling() {
        poller?.cancel()
        poller = nil
    }

    private func openSpotify() {
        guard let url = URL(string: "spotify:"), UIApplication.shared.canOpenURL(url) else {
            note("Installe Spotify, ou lance la lecture sur un autre appareil.")
            return
        }
        UIApplication.shared.open(url)
    }

    private func note(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: .seconds(Self.noticeSeconds))
            if notice == text { notice = nil }
        }
    }

    private static let noticeSeconds = 5.0

    /// What Spotify refused, in a sentence.
    private static func refusal(_ json: [String: Any]?) -> String {
        let error = json?["error"] as? [String: Any]
        let reason = error?["reason"] as? String ?? ""
        let message = (error?["message"] as? String ?? "").lowercased()
        if reason == "PREMIUM_REQUIRED" || message.contains("premium") {
            return "Spotify Premium est nécessaire pour piloter la lecture."
        }
        if message.contains("developer dashboard") || message.contains("not registered") {
            return "Ce compte Spotify n'est pas encore autorisé (mode test)."
        }
        return "Spotify a refusé la demande."
    }

    private static let pollSeconds = 4.0

    private static func call(_ method: String, _ path: String, token: String) async -> (status: Int, json: [String: Any]?)? {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/\(path)")!, timeoutInterval: 8)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if method != "GET" { request.setValue("0", forHTTPHeaderField: "Content-Length") }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return nil }
        let json = data.isEmpty ? nil : (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (http.statusCode, json)
    }

    private static func image(_ url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}
