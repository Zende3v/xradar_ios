import SwiftUI
import XRadarCore
import XRadarData

/// Réglages, as on Android: appearance, sharing the position with other drivers, and the admin's
/// backend diagnostic. The alerts are set from the HUD's "Options" dock.
struct SettingsScreen: View {
    let services: AppServices

    var body: some View {
        let preferences = services.preferences
        Form {
            Section("Apparence") {
                segmented(
                    "Thème de l'app",
                    selection: Binding(
                        get: { preferences.settings.themeMode },
                        set: { mode in preferences.updateSettings { $0.themeMode = mode } }
                    ),
                    options: [("Système", ThemeMode.system), ("Clair", .light), ("Sombre", .dark)]
                )
                segmented(
                    "Fond de carte",
                    selection: Binding(
                        get: { preferences.settings.mapStyle },
                        set: { style in preferences.updateSettings { $0.mapStyle = style } }
                    ),
                    options: [("Auto", MapStyle.auto), ("Clair", .bright), ("Sombre", .dark)],
                    hint: "Auto suit le jour et la nuit à ta position : clair de jour, sombre de nuit."
                )
            }

            Section("Communauté") {
                Toggle(isOn: Binding(
                    get: { preferences.alerts.liveVisible },
                    set: { visible in preferences.updateAlerts { $0.liveVisible = visible } }
                )) {
                    XRadarListRow(title: "Visible par les autres", icon: .symbol(.user), tint: XRadarColor.accent)
                }
                .tint(XRadarColor.accent)

                VStack(alignment: .leading, spacing: XRadarSpacing.sm) {
                    HStack {
                        Text("Rayon des usagers")
                            .font(.xrBody)
                            .foregroundStyle(XRadarColor.textPrimary)
                        Spacer()
                        Text("\(preferences.alerts.liveRadiusKm) km")
                            .font(.xrCallout.monospacedDigit())
                            .foregroundStyle(XRadarColor.accent)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(preferences.alerts.liveRadiusKm) },
                            set: { value in
                                preferences.updateAlerts {
                                    $0.liveRadiusKm = min(max(Int(value), AlertPreferences.minLiveKm), AlertPreferences.maxLiveKm)
                                }
                            }
                        ),
                        in: Double(AlertPreferences.minLiveKm)...Double(AlertPreferences.maxLiveKm),
                        step: 1
                    )
                    .tint(XRadarColor.accent)
                }
            }

            if services.account.account?.role == .admin {
                Section("Développeur") {
                    NavigationLink {
                        DiagnosticScreen(services: services)
                    } label: {
                        XRadarListRow(title: "Diagnostic backend", icon: .symbol(.diagnostic), tint: XRadarColor.accent)
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
