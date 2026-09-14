import SwiftUI
import UIKit
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
        let theme = services.preferences.settings.themeMode
        // Read here, in a view, so a change in Réglages applies at once (not only at the next launch).
        content
            .preferredColorScheme(theme.colorScheme)
            .onChange(of: theme, initial: true) { _, mode in
                applyToWindows(mode)
            }
    }

    @ViewBuilder
    private var content: some View {
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

    /// The theme on the windows too: `preferredColorScheme(nil)` alone may leave a forced look in
    /// place instead of following the phone again, and the full-screen covers must follow it.
    private func applyToWindows(_ mode: ThemeMode) {
        let style: UIUserInterfaceStyle = switch mode {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
