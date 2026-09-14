import SwiftUI
import XRadarData

/// Why the app needs the position, then iOS's own question. Whatever the answer (or "Plus
/// tard"), the app goes on, as on Android; a refusal made earlier goes straight on too, since iOS
/// asks only once.
struct LocationPermissionView: View {
    let location: LocationState
    let tracker: LocationTracker
    let onProceed: () -> Void

    @State private var asked = false

    var body: some View {
        XRadarMessageState(
            icon: .symbol(.gps),
            title: "Activer la localisation",
            message: "x_radar utilise ta position pour la navigation en temps réel et les alertes radars sur ta route. Ta position n'est jamais partagée sans ton accord.",
            tint: XRadarColor.accent,
            primaryLabel: "Autoriser la localisation",
            onPrimary: { allow() },
            secondaryLabel: "Plus tard",
            onSecondary: onProceed
        )
        .background(XRadarColor.canvas)
        .onChange(of: location.authorization) { _, authorization in
            if asked, authorization != .notDetermined { onProceed() }
        }
        .accessibilityIdentifier("screen.permission")
    }

    private func allow() {
        guard location.authorization == .notDetermined else {
            onProceed()
            return
        }
        asked = true
        tracker.requestAuthorization()
    }
}

#Preview {
    let location = LocationState()
    LocationPermissionView(location: location, tracker: LocationTracker(state: location)) {}
}
