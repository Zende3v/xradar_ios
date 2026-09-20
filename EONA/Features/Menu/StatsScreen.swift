import SwiftUI
import EonaCore
import EonaData

/// Statistiques: time and distance on the road with the app, how good a reporter the driver is,
/// and the trip history. Everything comes from the server, so it survives a reinstall.
struct StatsScreen: View {
    let account: AccountStore

    @State private var stats: AccountStats?
    @State private var loaded = false

    private static let maxTrips = 30

    var body: some View {
        Group {
            if !loaded {
                EonaLoadingState(label: "Chargement…")
            } else if let stats {
                content(stats)
            } else {
                EonaMessageState(
                    icon: .symbol(.info),
                    title: "Statistiques indisponibles",
                    message: "Impossible de joindre le serveur. Réessaie plus tard."
                )
            }
        }
        .background(EonaColor.canvas)
        .navigationTitle("Statistiques")
        .task {
            stats = await account.stats()
            loaded = true
        }
    }

    private func content(_ stats: AccountStats) -> some View {
        Form {
            Section {
                HStack(spacing: EonaSpacing.md) {
                    tile(StatsLabels.hours(seconds: stats.driveSeconds), "Sur la route", EonaColor.accent)
                    tile(StatsLabels.kilometers(meters: stats.distanceMeters), "Parcourus", EonaColor.textPrimary)
                    tile(String(stats.tripCount), "Trajets", EonaColor.textPrimary)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("Note de confiance") {
                    TrustStars(score: stats.trust)
                }
                LabeledContent("Alertes traversées", value: StatsLabels.grouped(stats.alertsTraversed))
                LabeledContent("Signalements déclarés", value: StatsLabels.grouped(stats.reportsDeclared))
                LabeledContent("Confirmés par d'autres", value: StatsLabels.grouped(stats.reportsConfirmed))
            } header: {
                Text("Signaleur")
            } footer: {
                Text("La note compare tes signalements confirmés à ceux que tu as déclarés. Elle démarre à 2,5 et monte à mesure que la communauté valide ce que tu signales.")
            }

            Section("Historique des trajets") {
                if stats.trips.isEmpty {
                    Text("Aucun trajet pour l'instant")
                        .foregroundStyle(EonaColor.textSecondary)
                } else {
                    ForEach(Array(stats.trips.prefix(Self.maxTrips)), id: \.id) { trip in
                        NavigationLink {
                            TripDetailScreen(trip: trip)
                        } label: {
                            EonaListRow(title: trip.toLabel, subtitle: "\(trip.dateLabel) · \(trip.distanceLabel) · \(trip.durationLabel)") {
                                if let delay = trip.delayLabel {
                                    Text(delay)
                                        .font(.xrCaption)
                                        .foregroundStyle(EonaColor.textTertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: EonaSpacing.xs) {
            Text(value)
                .font(.xrTitle.monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.xrCaption)
                .foregroundStyle(EonaColor.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .xrCard(padding: EonaSpacing.md)
    }
}
