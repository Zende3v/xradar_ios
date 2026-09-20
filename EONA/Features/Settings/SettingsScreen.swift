import SwiftUI
import EonaCore
import EonaData

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
                accentPicker(preferences)
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
                        EonaListRow(title: "Diagnostic backend", icon: .symbol(.diagnostic), glow: true)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(EonaColor.canvas)
        .navigationTitle("Réglages")
    }

    /// A volume from 0 to 100 %.
    private func volume(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: EonaSpacing.xs) {
            HStack {
                Text(title)
                    .font(.xrBody)
                    .foregroundStyle(EonaColor.textPrimary)
                Spacer(minLength: 0)
                Text("\(Int((value.wrappedValue * 100).rounded())) %")
                    .font(.xrCallout)
                    .monospacedDigit()
                    .foregroundStyle(EonaColor.textSecondary)
            }
            Slider(value: value, in: 0...1, step: 0.05)
                .tint(EonaColor.accent)
                .accessibilityLabel(title)
        }
        .padding(.vertical, EonaSpacing.xs)
    }

    /// "Couleur de l'app": the tint of everything interactive, and of the route drawn on the map.
    @ViewBuilder
    private func accentPicker(_ preferences: PreferencesStore) -> some View {
        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            Text("Couleur de l'app")
                .font(.xrBody)
                .foregroundStyle(EonaColor.textPrimary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: EonaSpacing.sm), count: 6), spacing: EonaSpacing.sm) {
                ForEach(AccentColor.allCases, id: \.self) { colour in
                    let chosen = preferences.settings.accent == colour
                    Circle()
                        .fill(swatch(colour))
                        .frame(height: 34)
                        .overlay {
                            Circle().strokeBorder(EonaColor.textPrimary, lineWidth: chosen ? 2.5 : 0)
                        }
                        .contentShape(.circle)
                        .accessibilityLabel(colour.label)
                        .onTapGesture {
                            preferences.updateSettings { $0.accent = colour }
                        }
                }
            }
            Text("La teinte des boutons, du tracé du trajet et des détails de l'interface.")
                .font(.xrFootnote)
                .foregroundStyle(EonaColor.textSecondary)
        }
        .padding(.vertical, EonaSpacing.xs)
    }

    private func swatch(_ colour: AccentColor) -> Color {
        Color(
            red: Double((colour.value >> 16) & 0xFF) / 255,
            green: Double((colour.value >> 8) & 0xFF) / 255,
            blue: Double(colour.value & 0xFF) / 255
        )
    }

    /// One row, one choice among a few: the title, the segments, an optional hint.
    private func segmented<Value: Hashable>(
        _ title: String,
        selection: Binding<Value>,
        options: [(String, Value)],
        hint: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            Text(title)
                .font(.xrBody)
                .foregroundStyle(EonaColor.textPrimary)
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
                    .foregroundStyle(EonaColor.textTertiary)
            }
        }
        .padding(.vertical, EonaSpacing.xs)
    }
}
