import SwiftUI
import EonaCore
import EonaData

/// App root, like the Android EonaApp: the location screen first (on every launch without the
/// permission, until the driver answers), then onboarding until the account has a username, then
/// the driving screen, where tracking starts if the position is allowed.
struct AppRoot: View {
    let services: AppServices
    /// A trip someone shared, opened from its link; the follow screen covers everything.
    @Binding var followToken: String?
    /// A group trip shared to be watched, opened from its own link.
    @Binding var watchToken: String?

    @State private var proceed: Bool
    /// Lives with the app, as the Android DriveViewModel lives with its start destination.
    @State private var drive: DriveModel
    @State private var menuOpen = false
    @State private var searchOpen = false
    /// The offers shown over the map, and why.
    @State private var paywall: PaywallReason?
    @State private var wasInBackground = false
    @Environment(\.scenePhase) private var scenePhase

    init(
        services: AppServices,
        followToken: Binding<String?> = .constant(nil),
        watchToken: Binding<String?> = .constant(nil)
    ) {
        self.services = services
        _followToken = followToken
        _watchToken = watchToken
        _proceed = State(initialValue: services.location.authorization == .granted)
        _drive = State(initialValue: DriveModel(services: services))
    }

    var body: some View {
        // Read in a view of its own, so a change in Réglages (or the sun) applies at once. The
        // theme goes on the window itself: every screen, sheet and full-screen cover follows it
        // together (preferredColorScheme mixed them badly).
        content
            // The chosen accent colour is read when a colour resolves: setting it and changing the
            // identity rebuilds every screen with it.
            .id(services.preferences.settings.accent)
            .onChange(of: services.preferences.settings.accent, initial: true) { _, accent in
                EonaColor.accentValue = accent.value
            }
            .background(AppThemeHost(preferences: services.preferences, location: services.location))
    }

    @ViewBuilder
    private var content: some View {
        if services.preferences.needsTerms(required: Terms.version) {
            // Rien ne démarre avant l'accord : c'est la condition d'usage de l'app.
            TermsScreen(preferences: services.preferences, account: services.account)
        } else if services.account.account?.isOnboarded != true {
            OnboardingView(account: services.account)
        } else if !proceed {
            // La position est demandée ici, quand la carte et le guidage en ont besoin : l'invite
            // du système suit tout de suite.
            LocationPermissionView(location: services.location, tracker: services.locationTracker) {
                proceed = true
            }
        } else {
            // The search lies over the HUD, in glass: the map and the HUD show through it.
            ZStack {
                DriveScreen(
                    services: services,
                    model: drive,
                    onOpenSearch: { showSearch(true) },
                    onOpenMenu: { menuOpen = true },
                    onBlocked: { paywall = $0 }
                )
                // The search's keyboard must not lift the HUD under it.
                .ignoresSafeArea(.keyboard)
                .accessibilityHidden(searchOpen)

                if searchOpen {
                    SearchScreen(services: services) { showSearch(false) }
                        .transition(.opacity)
                }
            }
            .task {
                services.locationTracker.start()
                offerIfRestricted()
            }
            .fullScreenCover(isPresented: $menuOpen) {
                MenuScreen(services: services, drive: drive) { menuOpen = false }
            }
            // Un lien de trajet ouvre le suivi par-dessus tout le reste.
            .fullScreenCover(item: Binding(get: { followToken.map(SharedTripLink.init) }, set: { followToken = $0?.token })) { link in
                FollowTripScreen(services: services, shareToken: link.token) { followToken = nil }
            }
            // Un lien de trajet en groupe ouvre la carte commune, en observateur.
            .fullScreenCover(item: Binding(get: { watchToken.map(SharedTripLink.init) }, set: { watchToken = $0?.token })) { link in
                GroupWatchScreen(services: services, linkToken: link.token) { watchToken = nil }
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

    private func showSearch(_ open: Bool) {
        withAnimation(.smooth(duration: 0.25)) {
            searchOpen = open
        }
    }

    /// The offers over the map when the account is blocked, unless a screen covers the map.
    private func offerIfRestricted() {
        guard services.account.account?.isRestricted == true, paywall == nil, !menuOpen, !searchOpen else { return }
        paywall = .restricted
    }
}

/// A shared trip's token, wrapped so a full-screen cover can be driven by it.
struct SharedTripLink: Identifiable {
    let token: String
    var id: String { token }
}
