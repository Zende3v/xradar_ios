import SwiftUI
import XRadarCore

/// One trip of the history: the real time against the estimate, distance, speeds, stops, and the
/// alerts met on the way. Time in traffic jams comes later.
struct TripDetailScreen: View {
    let trip: TripRecord

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: XRadarSpacing.xs) {
                    Text(trip.toLabel)
                        .font(.xrTitle)
                        .foregroundStyle(XRadarColor.textPrimary)
                    Text(trip.dateLabel)
                        .font(.xrSubhead)
                        .foregroundStyle(XRadarColor.textSecondary)
                }
                .padding(.vertical, XRadarSpacing.xs)
            }

            Section("Temps") {
                LabeledContent("Temps réel", value: trip.durationLabel)
                LabeledContent("Temps prévu", value: trip.plannedLabel ?? "Inconnu")
                if let delay = trip.delayLabel {
                    LabeledContent("Écart", value: delay)
                }
            }

            Section("Conduite") {
                LabeledContent("Kilomètres", value: trip.distanceLabel)
                LabeledContent("Vitesse moyenne", value: "\(trip.averageSpeedKmh) km/h")
                LabeledContent("Vitesse max", value: "\(trip.topSpeedKmh) km/h")
                LabeledContent("Arrêts", value: trip.stopsLabel)
                LabeledContent("Temps dans les bouchons") {
                    XRadarBadge(text: "Bientôt", glow: true)
                }
            }

            Section("Événements rencontrés") {
                let kinds = AlertType.allCases.filter { (trip.events[$0] ?? 0) > 0 }
                if kinds.isEmpty {
                    // Trips recorded before the detail was kept only have a total.
                    Text(trip.alertsCount > 0 ? "\(trip.alertsCount) alertes" : "Aucun")
                        .foregroundStyle(XRadarColor.textSecondary)
                } else {
                    ForEach(kinds, id: \.self) { type in
                        XRadarListRow(title: type.tripLabel, icon: type.icon, glow: true) {
                            Text("\(trip.events[type] ?? 0)")
                                .font(.xrNumeric)
                                .foregroundStyle(XRadarColor.textSecondary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(XRadarColor.canvas)
        .navigationTitle("Trajet")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension AlertType {
    var tripLabel: String {
        switch self {
        case .radarFixed: "Radars fixes"
        case .radarMobile: "Radars mobiles"
        case .controlZone: "Zones de contrôle"
        case .camera: "Caméras"
        case .hazard: "Dangers"
        case .accident: "Accidents"
        case .roadwork: "Travaux"
        case .radarCar: "Voitures radar"
        }
    }
}
