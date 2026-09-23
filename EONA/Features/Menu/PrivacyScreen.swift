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
                Text("Les destinations que tu choisis restent sur ce téléphone pour te les proposer dans la recherche (« Récents »). Désactivé : plus rien n'est gardé et la liste est effacée.")
            }

            Section {
                toggle("Aide au trafic partagé", \.sharedTraffic) {
                    // Its recent slowdowns leave the shared traffic too.
                    Task { await TrafficAPI(client: services.client).dismissProbe(token: services.account.token) }
                }
            } header: {
                Text("Trafic")
            } footer: {
                Text("Ta participation à l'évitement des bouchons : sur une route à 70 km/h ou plus, quand tu roules nettement moins vite que la limite, l'app envoie la position, le sens et la vitesse de ce moment, sans lien avec ton compte, effacés après 30 minutes. À plusieurs, cela signale un bouchon aux autres ; seul, l'app te demande « Ralentissement du trafic ? ». Désactivé : ta position n'alimente plus le trafic partagé. Le trafic sur ton trajet et « Éviter les bouchons » restent disponibles.")
            }

            Section {
                toggle("Statistiques de conduite", \.drivingStats)
                toggle("Présence et position", \.presence)
                toggle("Temps d'utilisation", \.usageTime)
            } header: {
                Text("Statistiques")
            } footer: {
                Text("Statistiques de conduite : tes trajets et ton temps de conduite, enregistrés sur ton compte (Menu ▸ Statistiques) ; désactivé, les prochains ne sont plus enregistrés. Présence et position : le serveur compte les apps ouvertes et les trajets en cours, et l'équipe EONA voit où tu es pendant que l'app est ouverte ; les positions sont effacées au bout de 30 jours. Temps d'utilisation : le temps passé dans l'app s'ajoute à ton compte.")
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
                    Text("En touchant ta photo, les autres membres d'un trajet en groupe ouvrent ta fiche : photo, pseudo, statut, mois d'inscription et note de confiance, toujours. Tes kilomètres, ton temps de conduite, tes trajets et tes signalements, seulement si c'est activé. Personne en dehors du groupe ne la voit.")
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
