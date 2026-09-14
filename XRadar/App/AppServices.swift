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
    let speaker = GuidanceSpeaker()

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        client = BackendClient(configuration: configuration.backend)
        account = AccountStore(api: AccountAPI(client: client), secrets: KeychainStore())
        locationTracker = LocationTracker(state: location)
        // The cached session, before the first frame: no onboarding flash for a known driver.
        account.restore()
    }
}
