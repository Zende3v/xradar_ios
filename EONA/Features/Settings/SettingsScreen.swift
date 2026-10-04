import SwiftUI
import EonaCore
import EonaData

/// Réglages : apparence, véhicule (curseur, et 45 km/h pour scooter 50 et sans permis),
/// protection pluie, permis probatoire, dépassement, volumes, diagnostic admin. Alertes : dock
/// « Options » du HUD. Données gardées et partagées : Menu ▸ Confidentialité.
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
                    hint: "Auto : clair de jour, sombre de nuit."
                )
                accentPicker(preferences)
            }

            Section {
                VehiclePicker(selection: preferences.vehicleType) { type in
                    preferences.setVehicleType(type)
                }
                Toggle(isOn: Binding(
                    get: { preferences.settings.rainLock },
                    set: { on in preferences.updateSettings { $0.rainLock = on } }
                )) {
                    Text("Protection pluie")
                        .font(.xrBody)
                        .foregroundStyle(EonaColor.textPrimary)
                }
                .tint(EonaColor.accent)
            } header: {
                Text("Véhicule")
            } footer: {
                Text("Protection pluie : écran verrouillé dès 15 km/h.")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { preferences.settings.probationary },
                    set: { on in preferences.updateSettings { $0.probationary = on } }
                )) {
                    Text("Permis probatoire")
                        .font(.xrBody)
                        .foregroundStyle(EonaColor.textPrimary)
                }
                .tint(EonaColor.accent)
            } header: {
                Text("Conduite")
            } footer: {
                Text("110 km/h sur autoroute, 100 sur voie rapide, 80 sur route.")
            }

            Section("Alertes") {
                segmented(
                    "Dépassement limitation",
                    selection: Binding(
                        get: { preferences.alerts.overspeed },
                        set: { warning in preferences.updateAlerts { $0.overspeed = warning } }
                    ),
                    options: [("Vocal", OverspeedWarning.voice), ("Bip", .beep), ("Aucun", .off)],
                    hint: "Au-delà de 5 km/h, rappel chaque minute."
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

    /// « Couleur de l'app » : boutons, tracé du trajet, détails.
    private func accentPicker(_ preferences: PreferencesStore) -> some View {
        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            HStack {
                Text("Couleur de l'app")
                    .font(.xrBody)
                    .foregroundStyle(EonaColor.textPrimary)
                Spacer(minLength: 0)
                Text(preferences.settings.accent.label)
                    .font(.xrCallout)
                    .foregroundStyle(EonaColor.textSecondary)
            }
            AccentSlider(selection: preferences.settings.accent) { colour in
                preferences.updateSettings { $0.accent = colour }
            }
        }
        .padding(.vertical, EonaSpacing.xs)
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

/// La palette en piste, un cran par teinte : glisser ou toucher choisit.
private struct AccentSlider: View {
    let selection: AccentColor
    let onPick: (AccentColor) -> Void

    private static let colours = AccentColor.allCases
    private static let thumb: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let step = proxy.size.width / CGFloat(Self.colours.count)
            let index = Self.colours.firstIndex(of: selection) ?? 0
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Self.colours, id: \.self) { colour in
                        Rectangle().fill(Self.swatch(colour))
                    }
                }
                .frame(height: 12)
                .clipShape(.capsule)
                Circle()
                    .fill(Self.swatch(selection))
                    .frame(width: Self.thumb, height: Self.thumb)
                    .overlay { Circle().strokeBorder(.white, lineWidth: 3) }
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .offset(x: step * (CGFloat(index) + 0.5) - Self.thumb / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    guard step > 0 else { return }
                    let picked = Self.colours[min(max(Int(value.location.x / step), 0), Self.colours.count - 1)]
                    if picked != selection { onPick(picked) }
                }
            )
        }
        .frame(height: Self.thumb + 4)
        .sensoryFeedback(.selection, trigger: selection)
        .animation(.snappy, value: selection)
        .accessibilityElement()
        .accessibilityLabel("Couleur de l'app")
        .accessibilityValue(selection.label)
        .accessibilityAdjustableAction { direction in
            let index = Self.colours.firstIndex(of: selection) ?? 0
            switch direction {
            case .increment: if index + 1 < Self.colours.count { onPick(Self.colours[index + 1]) }
            case .decrement: if index > 0 { onPick(Self.colours[index - 1]) }
            @unknown default: break
            }
        }
    }

    static func swatch(_ colour: AccentColor) -> Color {
        Color(
            red: Double((colour.value >> 16) & 0xFF) / 255,
            green: Double((colour.value >> 8) & 0xFF) / 255,
            blue: Double(colour.value & 0xFF) / 255
        )
    }
}
