import SwiftUI
import XRadarCore
import XRadarData

/// App root, like the Android XRadarApp: the location screen first (on every launch without the
/// permission, until the driver answers), then onboarding until the account has a username, then
/// the driving screen, where tracking starts if the position is allowed.
struct AppRoot: View {
    let services: AppServices

    @State private var proceed: Bool
    /// Lives with the app, as the Android DriveViewModel lives with its start destination.
    @State private var drive: DriveModel
    @State private var menuOpen = false
    @State private var searchOpen = false

    init(services: AppServices) {
        self.services = services
        _proceed = State(initialValue: services.location.authorization == .granted)
        _drive = State(initialValue: DriveModel(services: services))
    }

    var body: some View {
        if !proceed {
            LocationPermissionView(location: services.location, tracker: services.locationTracker) {
                proceed = true
            }
        } else if services.account.account?.isOnboarded != true {
            OnboardingView(account: services.account)
        } else {
            DriveScreen(
                services: services,
                model: drive,
                onOpenSearch: { searchOpen = true },
                onOpenMenu: { menuOpen = true }
            )
            .task { services.locationTracker.start() }
            .fullScreenCover(isPresented: $searchOpen) {
                SearchScreen(services: services) { searchOpen = false }
            }
            .fullScreenCover(isPresented: $menuOpen) {
                MenuScreen(services: services) { menuOpen = false }
            }
        }
    }
}
