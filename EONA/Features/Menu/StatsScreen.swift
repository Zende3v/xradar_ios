import SwiftUI
import EonaCore
import EonaData

/// Statistiques: time and distance on the road with the app, how good a reporter the driver is,
/// and the trip history. Everything comes from the server, so it survives a reinstall.
struct StatsScreen: View {
    let account: AccountStore
    /// The trips kept on this phone: a group trip's ranking lives there, not on the server.
    let history: TripHistoryStore

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
            stats = await account.stats().map(withGroups)
            loaded = true
        }
    }

    /// The server's trips, each with the group ranking this phone kept for it (same id).
    private func withGroups(_ stats: AccountStats) -> AccountStats {
        let groups = Dictionary(
            history.trips.compactMap { trip in trip.group.map { (trip.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        guard !groups.isEmpty else { return stats }
        return AccountStats(
            tripCount: stats.tripCount,
            distanceMeters: stats.distanceMeters,
            driveSeconds: stats.driveSeconds,
            alertsTraversed: stats.alertsTraversed,
            reportsDeclared: stats.reportsDeclared,
            reportsConfirmed: stats.reportsConfirmed,
            trust: stats.trust,
            trips: stats.trips.map { trip in groups[trip.id].map { trip.with(group: $0) } ?? trip }
        )
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
                            EonaListRow(
                                title: trip.toLabel,
                                subtitle: "\(trip.dateLabel) · \(trip.distanceLabel) · \(trip.durationLabel)",
                                icon: trip.group == nil ? nil : EonaIconImage.symbol(.people),
                                glow: trip.group != nil
                            ) {
                                if let group = trip.group {
                                    // Un trajet en groupe : le rang remplace l'écart sur l'estimation.
                                    Text(group.standingLabel)
                                        .font(.xrCaption)
                                        .foregroundStyle(EonaColor.accent)
                                } else if let delay = trip.delayLabel {
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
