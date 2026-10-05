import SwiftUI
import EonaCore
import EonaData

/// Réglages : apparence, véhicule (curseur, et 45 km/h pour scooter 50 et sans permis),
/// protection pluie, permis probatoire, dépassement, volumes, diagnostic admin. Alertes : dock
/// « Options » du HUD. Données gardées et partagées : Menu ▸ Confidentialité.
struct SettingsScreen: View {
    let services: AppServices
    @State private var offers: PaywallReason?

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
                VehiclePicker(selection: preferences.vehicleType, hasPlus: services.account.hasPlus) { type in
                    guard !type.requiresPlus || services.account.hasPlus else {
                        offers = type == .taxi ? .taxi : .truck
                        return
                    }
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
                segmented(
                    "Carburant préféré",
                    selection: Binding(
                        get: { preferences.settings.preferredFuel },
                        set: { fuel in
                            preferences.updateSettings {
                                $0.preferredFuel = fuel
                                $0.fuelNearestOnly = false
                            }
                        }
                    ),
                    options: FuelType.allCases.map { ($0.label, $0) }
                )
                consumptionSlider(preferences)
            } header: {
                Text("Carburant")
            } footer: {
                Text("Filtre des stations proches. Coût estimé des trajets.")
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
        .sheet(item: $offers) { reason in
            OffersSheet(reason: reason, account: services.account.account, store: services.account)
        }
    }

    /// « Consommation » : 1,0 à 30,0 L/100 km, cran de 0,1, valeur au dixième.
    private func consumptionSlider(_ preferences: PreferencesStore) -> some View {
        VStack(alignment: .leading, spacing: EonaSpacing.xs) {
            HStack {
                Text("Consommation")
                    .font(.xrBody)
                    .foregroundStyle(EonaColor.textPrimary)
                Spacer(minLength: 0)
                Text("\(Self.litres(preferences.settings.consumption)) L/100 km")
                    .font(.xrCallout)
                    .monospacedDigit()
                    .foregroundStyle(EonaColor.textSecondary)
            }
            Slider(
                value: Binding(
                    get: { preferences.settings.consumption },
                    set: { litres in preferences.updateSettings { $0.consumption = (litres * 10).rounded() / 10 } }
                ),
                in: AppSettings.consumptionRange,
                step: 0.1
            )
            .tint(EonaColor.accent)
            .accessibilityLabel("Consommation")
            .accessibilityValue("\(Self.litres(preferences.settings.consumption)) litres aux 100 kilomètres")
        }
        .padding(.vertical, EonaSpacing.xs)
    }

    /// "6,5".
    private static func litres(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
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

    /// Treize thèmes visibles. Accès gratuit ouvre offre, sans masquer palettes.
    private func accentPicker(_ preferences: PreferencesStore) -> some View {
        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            HStack {
                Text("Thème")
                    .font(.xrBody)
                    .foregroundStyle(EonaColor.textPrimary)
                Spacer(minLength: 0)
                Text(preferences.settings.accent.label)
                    .font(.xrCallout)
                    .foregroundStyle(EonaColor.textSecondary)
                if !services.account.hasPlus {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(EonaColor.textTertiary)
                }
            }
            ThemePicker(selection: preferences.settings.accent, hasPlus: services.account.hasPlus) { colour in
                guard services.account.hasPlus else { offers = .colours; return }
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

/// Choix directs : onze couleurs conservées, deux palettes sobres ajoutées.
private struct ThemePicker: View {
    let selection: AccentColor
    let hasPlus: Bool
    let onPick: (AccentColor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: EonaSpacing.xs)], alignment: .leading, spacing: EonaSpacing.xs) {
                ForEach(AccentColor.unicolours, id: \.self) { colour in
                    Button { onPick(colour) } label: {
                        Circle()
                            .fill(Self.swatch(colour.value))
                            .frame(width: 28, height: 28)
                            .padding(4)
                            .overlay { Circle().strokeBorder(selection == colour ? EonaColor.textPrimary : .clear, lineWidth: 1.5) }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(colour.label)
                    .accessibilityValue(selection == colour ? "Sélectionné" : "")
                    .accessibilityHint(hasPlus ? "Appliquer le thème" : "Voir EONA+")
                    .accessibilityAddTraits(selection == colour ? [.isSelected] : [])
                }
            }
            ForEach(AccentColor.palettes, id: \.self) { palette in
                Button { onPick(palette) } label: {
                    HStack(spacing: EonaSpacing.md) {
                        Circle()
                            .fill(LinearGradient(colors: palette.paletteValues.map(Self.swatch), startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 28, height: 28)
                        Text(palette.label)
                            .font(.xrCallout)
                            .foregroundStyle(EonaColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: EonaSpacing.sm)
                        if !hasPlus {
                            Image(systemName: "lock.fill").foregroundStyle(EonaColor.textTertiary)
                        } else if selection == palette {
                            Image(systemName: "checkmark").foregroundStyle(EonaColor.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(palette.label)
                .accessibilityValue(selection == palette ? "Sélectionné" : "")
                .accessibilityHint(hasPlus ? "Appliquer le thème" : "Voir EONA+")
                .accessibilityAddTraits(selection == palette ? [.isSelected] : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private static func swatch(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
