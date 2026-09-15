import Foundation
import Network
import XRadarData

/// The app's long-lived pieces, created once at launch and handed to the screens.
final class AppServices {
    let configuration: AppConfiguration
    let client: BackendClient
    let account: AccountStore
    let preferences = PreferencesStore()
    let savedPlaces = SavedPlacesStore()
    let recents = RecentsStore()
    let trips = TripHistoryStore()
    let activeTrip = ActiveTripStore()
    let location = LocationState()
    let locationTracker: LocationTracker
    let speaker: GuidanceSpeaker
    let alertSounds: AlertSoundPlayer
    let music = MusicPlayer()

    init(configuration: AppConfiguration) {
        // Some boxes and networks answer that the backend's name does not exist ("Safari ne trouve
        // pas le serveur"). Every lookup of the app goes over DNS-over-HTTPS (Cloudflare) instead:
        // Android only falls back to it after a failure, iOS offers the required mode only. TLS
        // still checks the real host's certificate.
        // Cloudflare's addresses are given too: the resolver itself must not need the network's DNS.
        NWParameters.PrivacyContext.default.requireEncryptedNameResolution(
            true,
            fallbackResolver: .https(
                URL(string: "https://cloudflare-dns.com/dns-query")!,
                serverAddresses: [.hostPort(host: "1.1.1.1", port: 443), .hostPort(host: "1.0.0.1", port: 443)]
            )
        )
        self.configuration = configuration
        // The voice and the alert sounds lower the music through one shared audio session.
        let focus = AudioFocus()
        speaker = GuidanceSpeaker(focus: focus)
        alertSounds = AlertSoundPlayer(focus: focus)
        client = BackendClient(configuration: configuration.backend)
        account = AccountStore(api: AccountAPI(client: client), secrets: KeychainStore())
        locationTracker = LocationTracker(state: location)
        // The cached session, before the first frame: no onboarding flash for a known driver.
        account.restore()
    }
}
