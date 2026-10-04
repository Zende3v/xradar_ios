import SwiftUI
import EonaData

/// « Véhicule » : une carte par véhicule, son curseur sur la carte, ses limites et ses routes ;
/// le choix cerclé d'accent.
struct VehiclePicker: View {
    let selection: VehicleType
    let onPick: (VehicleType) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: EonaSpacing.sm), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: EonaSpacing.sm) {
            ForEach(VehicleType.allCases, id: \.self) { type in
                card(type)
            }
        }
        .padding(.vertical, EonaSpacing.xs)
        .sensoryFeedback(.selection, trigger: selection)
        .animation(.snappy, value: selection)
    }

    private func card(_ type: VehicleType) -> some View {
        let chosen = type == selection
        return Button {
            onPick(type)
        } label: {
            VStack(spacing: EonaSpacing.xs) {
                Image(uiImage: MapImages.vehicle(type))
                    .renderingMode(.original)
                    .frame(width: MapImages.vehicleSize, height: MapImages.vehicleSize)
                Text(type.label)
                    .font(.xrCaption)
                    .foregroundStyle(chosen ? EonaColor.textPrimary : EonaColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(type.rules)
                    .font(.caption2)
                    .foregroundStyle(EonaColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, EonaSpacing.md)
            .padding(.horizontal, EonaSpacing.xs)
            .background(chosen ? EonaColor.accent.opacity(0.14) : Color.clear, in: .rect(cornerRadius: EonaRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: EonaRadius.md)
                    .strokeBorder(chosen ? EonaColor.accent : EonaColor.border, lineWidth: chosen ? 1.5 : 1)
            }
            .contentShape(.rect(cornerRadius: EonaRadius.md))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(type.label), \(type.rules.replacingOccurrences(of: "\n", with: ", "))")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

private extension VehicleType {
    /// Scooter 50, sans permis : limites et routes ; autres : curseur seul.
    var rules: String {
        moped ? "45 km/h max\nSans voie rapide" : "Esthétique"
    }
}
