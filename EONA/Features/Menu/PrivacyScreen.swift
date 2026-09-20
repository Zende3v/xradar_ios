import SwiftUI
import EonaCore
import EonaData

/// "Confidentialité": what the app keeps and shares, one switch each, each read by the system it
/// controls (the search, DriveModel). Off stops it at once; what it had kept goes where it can.
struct PrivacyScreen: View {
    let services: AppServices

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
                Text("Statistiques de conduite : tes trajets et ton temps de conduite, enregistrés sur ton compte (Menu ▸ Statistiques) ; désactivé, les prochains ne sont plus enregistrés. Présence et position : le serveur compte les apps ouvertes et les trajets en cours, et l'équipe XRadar voit où tu es pendant que l'app est ouverte ; les positions sont effacées au bout de 30 jours. Temps d'utilisation : le temps passé dans l'app s'ajoute à ton compte.")
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
