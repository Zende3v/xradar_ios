import SwiftUI
import XRadarCore
import XRadarData

/// Réglages: appearance, the overspeed warning, sharing slowdowns and the admin's backend diagnostic. Which alerts
/// show is set from the HUD's "Options" dock.
struct SettingsScreen: View {
    let services: AppServices

    var body: some View {
        let preferences = services.preferences
        Form {
            Section("Apparence") {
                segmented(
                    "Thème général",
                    selection: Binding(
                        get: { preferences.settings.theme },
                        set: { theme in preferences.updateSettings { $0.theme = theme } }
                    ),
                    options: [("Auto", AppTheme.auto), ("Jour", .day), ("Nuit", .night)],
                    hint: "L'app, la carte et le HUD ensemble. Auto suit le jour et la nuit à ta position : clair de jour, sombre de nuit."
                )
            }

            Section("Alertes") {
                segmented(
                    "Dépassement limitation",
                    selection: Binding(
                        get: { preferences.alerts.overspeed },
                        set: { warning in preferences.updateAlerts { $0.overspeed = warning } }
                    ),
                    options: [("Vocal", OverspeedWarning.voice), ("Bip", .beep), ("Aucun", .off)],
                    hint: "Plus de 5 km/h au-dessus de la limite, puis un rappel par minute tant que ça dure. Vocal suit le bouton des annonces vocales, Bip celui du son."
                )
            }

            Section {
                Toggle(isOn: Binding(
                    get: { preferences.settings.shareSlowdowns },
                    set: { on in preferences.updateSettings { $0.shareSlowdowns = on } }
                )) {
                    Text("Partager les ralentissements")
                        .font(.xrBody)
                        .foregroundStyle(XRadarColor.textPrimary)
                }
                .tint(XRadarColor.accent)
            } header: {
                Text("Trafic")
            } footer: {
                Text("Sur une route à 70 km/h ou plus, quand tu roules nettement moins vite que la limite, l'app envoie la position, le sens et la vitesse de ce moment, sans lien avec ton compte, effacés après 30 minutes. À plusieurs, cela signale un bouchon ; seul, l'app te demande « Ralentissement du trafic ? ».")
                    .font(.xrFootnote)
            }

            if services.account.account?.role == .admin {
                Section("Développeur") {
                    NavigationLink {
                        DiagnosticScreen(services: services)
                    } label: {
                        XRadarListRow(title: "Diagnostic backend", icon: .symbol(.diagnostic), glow: true)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(XRadarColor.canvas)
        .navigationTitle("Réglages")
    }

    /// One row, one choice among a few: the title, the segments, an optional hint.
    private func segmented<Value: Hashable>(
        _ title: String,
        selection: Binding<Value>,
        options: [(String, Value)],
        hint: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: XRadarSpacing.sm) {
            Text(title)
                .font(.xrBody)
                .foregroundStyle(XRadarColor.textPrimary)
            Picker(title, selection: selection) {
                ForEach(options, id: \.1) { option in
                    Text(option.0).tag(option.1)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let hint {
                Text(hint)
                    .font(.xrFootnote)
                    .foregroundStyle(XRadarColor.textTertiary)
            }
        }
        .padding(.vertical, XRadarSpacing.xs)
    }
}
