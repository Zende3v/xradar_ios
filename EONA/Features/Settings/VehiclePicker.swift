import SwiftUI
import EonaData

/// "Véhicule": one tile per vehicle, with the cursor it draws on the map; the chosen one is
/// outlined in the accent.
struct VehiclePicker: View {
    let selection: VehicleType
    let onPick: (VehicleType) -> Void

    var body: some View {
        HStack(spacing: EonaSpacing.sm) {
            ForEach(VehicleType.allCases, id: \.self) { type in
                let chosen = type == selection
                Button {
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
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, EonaSpacing.sm)
                    .background(chosen ? EonaColor.accent.opacity(0.14) : Color.clear, in: .rect(cornerRadius: EonaRadius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: EonaRadius.md)
                            .strokeBorder(chosen ? EonaColor.accent : EonaColor.border, lineWidth: chosen ? 1.5 : 1)
                    }
                    .contentShape(.rect(cornerRadius: EonaRadius.md))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(type.label)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(.vertical, EonaSpacing.xs)
    }
}
