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
    /// The offers shown over the map, and why.
    @State private var paywall: PaywallReason?
    @State private var wasInBackground = false
    @Environment(\.scenePhase) private var scenePhase

    init(services: AppServices) {
        self.services = services
        _proceed = State(initialValue: services.location.authorization == .granted)
        _drive = State(initialValue: DriveModel(services: services))
    }

    var body: some View {
        // Read here, in a view, so a change in Réglages applies at once. The theme goes on the
        // window itself: every screen, sheet and full-screen cover follows it together, and
        // "Système" hands the look back to the phone (preferredColorScheme mixed both badly).
        content
            .background(WindowTheme(style: services.preferences.settings.themeMode.interfaceStyle))
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
                onOpenMenu: { menuOpen = true },
                onBlocked: { paywall = $0 }
            )
            .task {
                services.locationTracker.start()
                offerIfRestricted()
            }
            .fullScreenCover(isPresented: $searchOpen) {
                SearchScreen(services: services) { searchOpen = false }
            }
            .fullScreenCover(isPresented: $menuOpen) {
                MenuScreen(services: services) { menuOpen = false }
            }
            .sheet(item: $paywall) { reason in
                OffersSheet(reason: reason, account: services.account.account)
            }
            // A blocked account sees the offers each time the app comes back to the front.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { wasInBackground = true }
                guard phase == .active, wasInBackground else { return }
                wasInBackground = false
                Task {
                    await services.account.reload()
                    offerIfRestricted()
                }
            }
            .onChange(of: services.account.account?.isRestricted == true) { _, restricted in
                if restricted { offerIfRestricted() }
            }
            .onChange(of: drive.denial) { _, denial in
                guard let denial else { return }
                drive.acknowledgeDenial()
                paywall = PaywallReason(denial)
            }
        }
    }

    /// The offers over the map when the account is blocked, unless a screen covers the map.
    private func offerIfRestricted() {
        guard services.account.account?.isRestricted == true, paywall == nil, !menuOpen, !searchOpen else { return }
        paywall = .restricted
    }
}

/// Sets the app's look on the window hosting it, as soon as it is attached (before the first
/// frame) and at every change.
private struct WindowTheme: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> WindowThemeView {
        let view = WindowThemeView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: WindowThemeView, context: Context) {
        view.style = style
    }
}

private final class WindowThemeView: UIView {
    var style: UIUserInterfaceStyle = .unspecified {
        didSet { apply() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        apply()
    }

    private func apply() {
        guard let window, window.overrideUserInterfaceStyle != style else { return }
        window.overrideUserInterfaceStyle = style
    }
}

private extension ThemeMode {
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}
