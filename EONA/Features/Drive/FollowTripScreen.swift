import MapKit
import SwiftUI
import EonaCore
import EonaData

/// The other side of "Partager mon trajet": someone opened a link, and follows the driver on the
/// map — where they are, the route they follow, what is left and when they arrive. It refreshes
/// on its own and closes itself once the share is over.
struct FollowTripScreen: View {
    let services: AppServices
    let shareToken: String
    let onClose: () -> Void

    @State private var trip: FollowedTrip?
    @State private var over = false
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .top) {
            map
                .ignoresSafeArea()

            header
                .padding(.horizontal, EonaSpacing.lg)
                .padding(.top, EonaSpacing.sm)
        }
        .background(EonaColor.canvas)
        .task(id: shareToken) { await watch() }
    }

    @ViewBuilder
    private var map: some View {
        Map(position: $camera) {
            if let trip, trip.route.count >= 2 {
                MapPolyline(coordinates: trip.route.map(Self.coordinate))
                    .stroke(EonaColor.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if let destination = trip?.destination {
                Annotation(trip?.toLabel ?? "Arrivée", coordinate: Self.coordinate(destination)) {
                    EonaIconView(icon: .symbol(.flag), size: 22)
                        .foregroundStyle(EonaColor.textPrimary)
                        .padding(EonaSpacing.xs)
                        .background(EonaColor.surface, in: .circle)
                }
            }
            if let position = trip?.position {
                Annotation(trip?.name ?? "", coordinate: Self.coordinate(position)) {
                    Circle()
                        .fill(EonaColor.accent)
                        .frame(width: 18, height: 18)
                        .overlay { Circle().strokeBorder(EonaColor.onAccent, lineWidth: 3) }
                        .shadow(radius: 4)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.xrHeadline)
                        .foregroundStyle(EonaColor.textPrimary)
                    Text(detail)
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textSecondary)
                }
                Spacer(minLength: EonaSpacing.md)
                EonaIconButton(icon: .symbol(.close), label: "Fermer", size: 40) { onClose() }
            }
            if over {
                Text("Ce partage est terminé.")
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textTertiary)
            }
        }
        .padding(EonaSpacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: EonaRadius.lg))
    }

    private var title: String {
        guard let trip else { return over ? "Partage terminé" : "Trajet partagé" }
        return trip.arrived ? "\(trip.name) est arrivé" : "\(trip.name) est en route"
    }

    private var detail: String {
        guard let trip, !trip.arrived else {
            return over ? "Le lien ne montre plus rien." : "En attente de sa position…"
        }
        var parts: [String] = []
        if let toLabel = trip.toLabel { parts.append("Vers \(toLabel)") }
        if let metres = trip.remainingMeters { parts.append(Self.distance(metres)) }
        if let eta = trip.etaAt { parts.append("arrivée \(Self.time(eta))") }
        return parts.isEmpty ? "Trajet en cours" : parts.joined(separator: " · ")
    }

    /// Asks again while the screen is open: the driver moves every ten seconds or so.
    private func watch() async {
        let api = TripShareAPI(client: services.client)
        while !Task.isCancelled {
            let seen = await api.follow(shareToken, token: services.account.token)
            if let seen {
                trip = seen
                if let position = seen.position, camera == .automatic || seen.arrived {
                    camera = .region(MKCoordinateRegion(
                        center: Self.coordinate(position),
                        latitudinalMeters: 4000,
                        longitudinalMeters: 4000
                    ))
                }
                if seen.arrived {
                    // Arrivé : on laisse la carte en place, sans plus rien demander.
                    over = true
                    return
                }
            } else {
                over = true
                return
            }
            try? await Task.sleep(for: .seconds(8))
        }
    }

    private static func coordinate(_ point: GeoPoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
    }

    /// "820 m", "12,4 km" — comme le HUD.
    private static func distance(_ metres: Int) -> String {
        if metres < 1000 { return "\(metres) m restants" }
        return String(format: "%.1f km restants", Double(metres) / 1000).replacingOccurrences(of: ".", with: ",")
    }

    private static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
