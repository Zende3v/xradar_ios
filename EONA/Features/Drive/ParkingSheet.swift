import SwiftUI
import EonaCore
import EonaData

/// « Véhicule garé » : depuis quand, à quelle distance, quel véhicule ; trajet à pied dans
/// Plans, ou repère retiré.
struct ParkingSheet: View {
    let parking: ParkingStore
    let location: LocationState
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        DriveSheet {
            if let spot = parking.spot {
                header(spot)
                VehicleRow(selected: spot.vehicle) { parking.setVehicle($0) }
                VStack(spacing: EonaSpacing.sm) {
                    EonaButton(title: "Y aller à pied", systemImage: .walk, fillWidth: true) { walk(to: spot) }
                    EonaButton(title: "Retirer le repère", variant: .secondary, fillWidth: true) {
                        parking.clear()
                        onClose()
                    }
                }
            } else {
                Text("Aucun véhicule garé.")
                    .font(.xrBody)
                    .foregroundStyle(EonaColor.textSecondary)
            }
        }
    }

    private func header(_ spot: ParkingSpot) -> some View {
        HStack(spacing: EonaSpacing.md) {
            Image(EonaSymbol.parking)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color(uiColor: MapImages.parkingBlue), in: .rect(cornerRadius: EonaRadius.md))
            VStack(alignment: .leading, spacing: 2) {
                Text("Véhicule garé")
                    .font(.xrTitle)
                    .foregroundStyle(EonaColor.textPrimary)
                // L'âge du repère avance seul, sheet ouverte.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(detail(spot, now: context.date))
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Garé il y a 12 min · à 350 m".
    private func detail(_ spot: ParkingSpot, now: Date) -> String {
        let age = "Garé \(ParkingSpot.ageLabel(since: spot.parkedAt, now: now))"
        guard let fix = location.location else { return age }
        let meters = Geo.haversine(lat1: fix.latitude, lon1: fix.longitude, lat2: spot.lat, lon2: spot.lon)
        return "\(age) · à \(RouteChoiceText.distance(Int(meters.rounded())))"
    }

    /// Plans, itinéraire à pied jusqu'au repère.
    private func walk(to spot: ParkingSpot) {
        guard let url = URL(string: "https://maps.apple.com/?daddr=\(spot.lat),\(spot.lon)&dirflg=w") else { return }
        openURL(url)
    }
}

/// Voiture, moto, vélo, trottinette : le véhicule retenu en accent.
private struct VehicleRow: View {
    let selected: ParkedVehicle
    let onSelect: (ParkedVehicle) -> Void

    var body: some View {
        HStack(spacing: EonaSpacing.sm) {
            ForEach(ParkedVehicle.allCases, id: \.self) { vehicle in
                let on = vehicle == selected
                Button {
                    onSelect(vehicle)
                } label: {
                    VStack(spacing: EonaSpacing.xs) {
                        Image(systemName: vehicle.symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .frame(height: 24)
                        Text(vehicle.label)
                            .font(.xrCaption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? EonaColor.accent : EonaColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, EonaSpacing.sm)
                    .background(on ? EonaColor.accent.opacity(0.12) : Color.clear, in: .rect(cornerRadius: EonaRadius.lg))
                    .overlay {
                        RoundedRectangle(cornerRadius: EonaRadius.lg)
                            .strokeBorder(on ? EonaColor.accent : EonaColor.border, lineWidth: on ? 1.5 : 1)
                    }
                    .contentShape(.rect(cornerRadius: EonaRadius.lg))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(vehicle.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
        .animation(.snappy, value: selected)
    }
}
