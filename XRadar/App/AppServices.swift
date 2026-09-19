import Foundation
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
