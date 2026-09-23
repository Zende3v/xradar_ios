import Foundation
import UIKit
import EonaData

/// The app's long-lived pieces, created once at launch and handed to the screens.
final class AppServices {
    /// The phone and the app, as the system describes them.
    static func appInfo() -> [String: String] {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let locale = Locale.current
        return [
            "platform": "ios",
            "model": model.isEmpty ? UIDevice.current.model : model,
            "osVersion": UIDevice.current.systemVersion,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—",
            "locale": locale.identifier,
            "region": locale.region?.identifier ?? "",
        ].filter { !$0.value.isEmpty }
    }

    let configuration: AppConfiguration
    let client: BackendClient
    let account: AccountStore
    let preferences = PreferencesStore()
    let savedPlaces = SavedPlacesStore()
    // Recents keep a copy in the Keychain: an update never loses them.
    let recents = RecentsStore(backup: KeychainStore())
    let trips = TripHistoryStore()
    let activeTrip = ActiveTripStore()
    let location = LocationState()
    let locationTracker: LocationTracker
    let speaker: GuidanceSpeaker
    let alertSounds: AlertSoundPlayer
    // Apple Music, or Spotify once the driver connected it (tokens in the Keychain).
    let music = MusicPlayer(spotify: SpotifyRemote(auth: SpotifyAuth(keychain: KeychainStore())))

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        // The voice and the alert sounds lower the music through one shared audio session.
        let focus = AudioFocus()
        speaker = GuidanceSpeaker(focus: focus)
        alertSounds = AlertSoundPlayer(focus: focus)
        client = BackendClient(configuration: configuration.backend)
        account = AccountStore(api: AccountAPI(client: client), secrets: KeychainStore())
        // What the app knows of itself, joined to a sign-up so the admin card is not empty:
        // the phone's model, its system, our version, the language of the device. Nothing more,
        // and nothing the system does not hand over freely — no advertising identifier.
        account.appInfo = AppServices.appInfo()
        locationTracker = LocationTracker(state: location)
        // The cached session, before the first frame: no onboarding flash for a known driver.
        account.restore()
    }
}
