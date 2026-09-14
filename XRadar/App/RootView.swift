import SwiftUI
import XRadarCore
import XRadarData

/// Temporary root until onboarding and the drive screen land (step 7). It checks the platform
/// layer on a real iPhone: GPS screen locked, voice, the Keychain session, the backend.
struct RootView: View {
    let services: AppServices

    @State private var checks: [CheckResult] = []
    @State private var checking = false

    var body: some View {
        NavigationStack {
            Form {
                positionSection
                accountSection
                Section("Voix") {
                    Button("Tester la voix") {
                        let step = RouteStep(location: GeoPoint(lat: 0, lon: 0), type: "turn", modifier: "right", name: "Rue de la Paix", distanceMeters: 300, exit: nil)
                        services.speaker.speak(GuidanceText.spokenFar(step, meters: 300))
                    }
                }
                serverSection
                Section("Interface") {
                    NavigationLink("Design system") { DesignSystemGallery() }
                }
            }
            .navigationTitle("Vérification iOS")
        }
        .accessibilityIdentifier("root.placeholder")
    }

    private var positionSection: some View {
        Section {
            LabeledContent("Autorisation", value: authorizationLabel)
            LabeledContent("Signal", value: signalLabel)
            if let sample = services.location.location {
                LabeledContent("Position", value: String(format: "%.5f, %.5f", sample.latitude, sample.longitude))
                LabeledContent("Vitesse", value: "\(Int(sample.speedKmh.rounded())) km/h")
                LabeledContent("Cap", value: sample.bearingDeg.map { "\(Int($0.rounded()))°" } ?? "—")
                LabeledContent("Précision", value: sample.accuracyM.map { "\(Int($0.rounded())) m" } ?? "—")
            }
            Button("Démarrer le suivi") { services.locationTracker.start() }
            Button("Arrêter le suivi", role: .destructive) { services.locationTracker.stop() }
        } header: {
            Text("Position")
        } footer: {
            Text("Verrouille l'écran pendant un trajet : en revenant, la position doit avoir avancé, et la pastille bleue reste en haut de l'écran.")
        }
    }

    private var accountSection: some View {
        Section("Compte") {
            LabeledContent("Appareil", value: String(services.account.deviceId.prefix(8)))
            LabeledContent("Compte", value: accountLabel)
            LabeledContent("Session", value: services.account.token == nil ? "aucune" : "active")
            Button("Rafraîchir") {
                Task { await services.account.refresh() }
            }
        }
    }

    private var serverSection: some View {
        Section("Serveur") {
            Button(checking ? "Vérification…" : "Lancer le diagnostic") {
                checking = true
                Task {
                    checks = await BackendDiagnostics(client: services.client).run()
                    checking = false
                }
            }
            .disabled(checking)
            ForEach(checks, id: \.name) { check in
                VStack(alignment: .leading, spacing: 4) {
                    Label(check.name, systemImage: check.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(check.ok ? .green : .red)
                    Text(check.detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
        }
    }

    private var authorizationLabel: String {
        switch services.location.authorization {
        case .notDetermined: "non demandée"
        case .denied: "refusée"
        case .granted: "accordée"
        }
    }

    private var signalLabel: String {
        switch services.location.signal {
        case .searching: "recherche…"
        case .good: "bon"
        case .weak: "faible"
        case .lost: "perdu"
        }
    }

    private var accountLabel: String {
        guard let account = services.account.account else { return "aucun" }
        return "\(account.username ?? "sans pseudo") · \(account.role.label)"
    }
}

#Preview {
    RootView(services: AppServices(configuration: AppConfiguration(info: [:])))
}
