import SwiftUI
import XRadarCore
import XRadarData

/// App root, like the Android XRadarApp: the location screen first (on every launch without the
/// permission, until the driver answers), then onboarding until the account has a username, then
/// the app, where tracking starts if the position is allowed.
struct AppRoot: View {
    let services: AppServices

    @State private var proceed: Bool

    init(services: AppServices) {
        self.services = services
        _proceed = State(initialValue: services.location.authorization == .granted)
    }

    var body: some View {
        if !proceed {
            LocationPermissionView(location: services.location, tracker: services.locationTracker) {
                proceed = true
            }
        } else if services.account.account?.isOnboarded != true {
            OnboardingView(account: services.account)
        } else {
            // Temporary until the drive screen lands (step 9).
            PlatformCheckView(services: services)
                .task { services.locationTracker.start() }
        }
    }
}
