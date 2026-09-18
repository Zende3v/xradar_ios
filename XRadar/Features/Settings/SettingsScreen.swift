import SwiftUI
import XRadarCore
import XRadarData

/// Réglages: appearance, the overspeed warning, the two volumes and the admin's backend
/// diagnostic. Which alerts show is set from the HUD's "Options" dock; what the app keeps and
/// shares, from Menu ▸ Confidentialité.
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
                volume(
                    "Volume Guidage",
                    Binding(
                        get: { preferences.alerts.guidanceVolume },
                        set: { value in preferences.updateAlerts { $0.guidanceVolume = value } }
                    )
                )
                volume(
                    "Volume alertes",
                    Binding(
                        get: { preferences.alerts.alertVolume },
                        set: { value in preferences.updateAlerts { $0.alertVolume = value } }
                    )
                )
            } header: {
                Text("Volume")
            } footer: {
                Text("Guidage : les consignes de navigation. Alertes : les sons et les annonces des radars, des dangers et du dépassement. Chacun indépendant de l'autre, dans la limite du volume du téléphone.")
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

    /// A volume from 0 to 100 %.
    private func volume(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: XRadarSpacing.xs) {
            HStack {
                Text(title)
                    .font(.xrBody)
                    .foregroundStyle(XRadarColor.textPrimary)
                Spacer(minLength: 0)
                Text("\(Int((value.wrappedValue * 100).rounded())) %")
                    .font(.xrCallout)
                    .monospacedDigit()
                    .foregroundStyle(XRadarColor.textSecondary)
            }
            Slider(value: value, in: 0...1, step: 0.05)
                .tint(XRadarColor.accent)
                .accessibilityLabel(title)
        }
        .padding(.vertical, XRadarSpacing.xs)
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
