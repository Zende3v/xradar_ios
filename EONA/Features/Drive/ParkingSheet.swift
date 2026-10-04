import SwiftUI
import EonaCore
import EonaData

/// « Stationnement » : repères posés, du plus récent au plus ancien. « Garer ici » en pose un ;
/// un repère ouvre sa fiche : véhicule, trajet à pied dans Plans, retrait.
struct ParkingSheet: View {
    let parking: ParkingStore
    let location: LocationState
    /// Véhicule d'un nouveau repère, tiré du véhicule des réglages.
    let vehicle: ParkedVehicle
    let onClose: () -> Void

    /// Repère ouvert ; nil : la liste.
    @State private var selected: String?
    @State private var noFix = false
    @State private var parkedCount = 0

    @Environment(\.openURL) private var openURL

    /// [focus] : repère touché sur la carte, sa fiche d'abord.
    init(parking: ParkingStore, location: LocationState, vehicle: ParkedVehicle, focus: String? = nil, onClose: @escaping () -> Void) {
        self.parking = parking
        self.location = location
        self.vehicle = vehicle
        self.onClose = onClose
        _selected = State(initialValue: focus)
    }

    var body: some View {
        DriveSheet {
            if let id = selected, let spot = parking.spot(id) {
                detail(spot)
            } else {
                list
            }
        }
        .sensoryFeedback(.success, trigger: parkedCount)
        .animation(.snappy, value: selected)
        .animation(.snappy, value: parking.spots.map(\.id))
    }

    // MARK: Liste

    @ViewBuilder
    private var list: some View {
        Text("Stationnement")
            .font(.xrTitle)
            .foregroundStyle(EonaColor.textPrimary)
        if parking.spots.isEmpty {
            Text("Aucun repère.")
                .font(.xrBody)
                .foregroundStyle(EonaColor.textSecondary)
        } else {
            VStack(spacing: EonaSpacing.sm) {
                ForEach(parking.spots) { spot in
                    Button {
                        selected = spot.id
                    } label: {
                        SpotLine(spot: spot, detail: { detailText(spot, now: $0) }, chevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        VStack(spacing: EonaSpacing.sm) {
            EonaButton(title: "Garer ici", systemImage: .parking, fillWidth: true, action: park)
            if noFix {
                Text("Position introuvable. Réessaie dans un instant.")
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Repère à la position actuelle ; sa fiche s'ouvre, pour choisir le véhicule.
    private func park() {
        guard let fix = location.location else {
            noFix = true
            return
        }
        noFix = false
        let spot = parking.park(lat: fix.latitude, lon: fix.longitude, vehicle: vehicle)
        parkedCount += 1
        selected = spot.id
    }

    // MARK: Fiche

    @ViewBuilder
    private func detail(_ spot: ParkingSpot) -> some View {
        SheetBackTitle(title: "Véhicule garé") { selected = nil }
        SpotLine(spot: spot, detail: { detailText(spot, now: $0) }, chevron: false)
        VehicleRow(selected: spot.vehicle) { parking.setVehicle($0, for: spot.id) }
        VStack(spacing: EonaSpacing.sm) {
            EonaButton(title: "Y aller à pied", systemImage: .walk, fillWidth: true) { walk(to: spot) }
            EonaButton(title: "Retirer le repère", variant: .secondary, fillWidth: true) {
                parking.remove(spot.id)
                if parking.spots.isEmpty { onClose() } else { selected = nil }
            }
        }
    }

    /// "Garé il y a 12 min · à 350 m".
    private func detailText(_ spot: ParkingSpot, now: Date) -> String {
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

/// Un repère : pastille du repère sur la carte, véhicule, âge et distance.
private struct SpotLine: View {
    let spot: ParkingSpot
    let detail: (Date) -> String
    let chevron: Bool

    var body: some View {
        HStack(spacing: EonaSpacing.md) {
            Image(systemName: spot.vehicle.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color(uiColor: MapImages.parkingBlue), in: .rect(cornerRadius: EonaRadius.md))
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.vehicle.label)
                    .font(.xrBodyStrong)
                    .foregroundStyle(EonaColor.textPrimary)
                // L'âge du repère avance seul, sheet ouverte.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(detail(context.date))
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if chevron {
                Image(EonaSymbol.chevronRight)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EonaColor.textTertiary)
            }
        }
        .padding(chevron ? EonaSpacing.sm : 0)
        .background(chevron ? EonaColor.surfaceHigh.opacity(0.6) : Color.clear, in: .rect(cornerRadius: EonaRadius.lg))
        .contentShape(.rect(cornerRadius: EonaRadius.lg))
        .accessibilityElement(children: .combine)
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
