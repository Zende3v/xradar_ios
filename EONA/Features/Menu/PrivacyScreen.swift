import SwiftUI
import EonaCore
import EonaData

/// "Confidentialité": what the app keeps and shares, one switch each, each read by the system it
/// controls (the search, DriveModel). Off stops it at once; what it had kept goes where it can.
struct PrivacyScreen: View {
    let services: AppServices

    /// The switch as the driver just set it, while the server is told.
    @State private var groupStatsPending: Bool?
    @State private var groupStatsError: String?

    var body: some View {
        Form {
            Section {
                toggle("Suggestions de trajets", \.tripSuggestions) {
                    services.recents.clear()
                }
            } header: {
                Text("Personnalisation")
            } footer: {
                Text("Garde tes destinations récentes sur ce téléphone. Désactiver efface la liste et arrête son enregistrement.")
            }

            Section {
                toggle("Aide au trafic partagé", \.sharedTraffic) {
                    // Its recent slowdowns leave the shared traffic too.
                    Task { await TrafficAPI(client: services.client).dismissProbe(token: services.account.token) }
                }
            } header: {
                Text("Trafic")
            } footer: {
                Text("Partage position, vitesse, sens, limitation et heure pendant le guidage. Certains ralentissements sont aussi partagés hors guidage. Ces données, sous identifiant temporaire, sont effacées après 30 minutes. Désactiver arrête ces envois ; le trafic reste disponible. La collecte des trajets décrite ci-dessous reste active.")
            }

            Section {
                toggle("Statistiques de conduite", \.drivingStats)
                toggle("Présence et position", \.presence)
                toggle("Temps d'utilisation", \.usageTime)
            } header: {
                Text("Statistiques")
            } footer: {
                Text("Conduite : ajoute trajets et temps de conduite à tes statistiques. Présence : indique l'app ouverte à EONA et partage ta position en guidage ou à la fermeture, conservée 30 jours. Temps d'utilisation : cumule le temps dans l'app. Même désactivés, les trajets guidés, mesures et tracés GPS sont envoyés pour améliorer l'arrivée estimée. Conservation sans limite de durée, jusqu'à suppression du compte.")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { groupStatsPending ?? services.account.account?.groupStatsVisible ?? true },
                    set: { on in setGroupStats(on) }
                )) {
                    Text("Statistiques visibles du groupe")
                        .font(.xrBody)
                        .foregroundStyle(EonaColor.textPrimary)
                }
                .tint(EonaColor.accent)
                .disabled(services.account.token == nil || groupStatsPending != nil)
            } header: {
                Text("Trajet en groupe")
            } footer: {
                VStack(alignment: .leading, spacing: EonaSpacing.xs) {
                    if let groupStatsError {
                        Text(groupStatsError)
                            .foregroundStyle(EonaColor.danger)
                    }
                    Text("Les membres du groupe voient toujours photo, pseudo, statut, mois d'inscription et note de confiance. Cette option ajoute kilomètres, temps de conduite, nombre de trajets et signalements.")
                }
            }

            Section {
                Link(destination: LegalScreen.privacy) {
                    EonaListRow(title: "Politique de confidentialité", icon: .symbol(.info), tint: EonaColor.accent)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(EonaColor.canvas)
        .navigationTitle("Confidentialité")
    }

    /// Saved on the account: the other members read it from the server.
    private func setGroupStats(_ on: Bool) {
        groupStatsPending = on
        groupStatsError = nil
        Task {
            if case .failure(let message) = await services.account.setGroupStatsVisible(on) {
                groupStatsError = message
            }
            groupStatsPending = nil
        }
    }

    /// One switch on [key]; [onOff] runs when the driver turns it off.
    private func toggle(_ title: String, _ key: WritableKeyPath<AppSettings, Bool>, onOff: @escaping () -> Void = {}) -> some View {
        let preferences = services.preferences
        return Toggle(isOn: Binding(
            get: { preferences.settings[keyPath: key] },
            set: { on in
                preferences.updateSettings { $0[keyPath: key] = on }
                if !on { onOff() }
            }
        )) {
            Text(title)
                .font(.xrBody)
                .foregroundStyle(EonaColor.textPrimary)
        }
        .tint(EonaColor.accent)
    }
}
