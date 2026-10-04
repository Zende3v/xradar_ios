import SwiftUI
import EonaCore
import EonaData

/// Étapes du trajet : ordre au glisser-déposer, retrait d'un geste, ajout en bas. Arrivée fixe,
/// en dernier. Chaque changement recalcule l'itinéraire.
struct StopsSheet: View {
    let trip: ActiveTripStore
    let onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if trip.stops.isEmpty {
                    Text("Aucune étape. Ajoute une adresse sur le trajet.")
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textSecondary)
                } else {
                    Section {
                        ForEach(Array(trip.stops.enumerated()), id: \.element.id) { index, stop in
                            StopRow(number: index + 1, place: stop)
                        }
                        .onMove(perform: move)
                        .onDelete(perform: remove)
                    } footer: {
                        Text("Glisse pour changer l'ordre.")
                    }
                }
                if let arrival = trip.destination ?? trip.proposal {
                    Section {
                        ArrivalRow(place: arrival)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .navigationTitle("Étapes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if trip.stops.count < ActiveTripStore.maxStops {
                    EonaButton(title: "Ajouter une étape", systemImage: .plus, variant: .secondary, fillWidth: true, action: onAdd)
                        .padding(.horizontal, EonaSpacing.lg)
                        .padding(.bottom, EonaSpacing.sm)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var stops = trip.stops
        stops.move(fromOffsets: source, toOffset: destination)
        trip.setStops(stops)
    }

    private func remove(at offsets: IndexSet) {
        var stops = trip.stops
        stops.remove(atOffsets: offsets)
        trip.setStops(stops)
    }
}

/// Une étape : son numéro, comme sur la carte, son nom, son adresse.
private struct StopRow: View {
    let number: Int
    let place: Place

    var body: some View {
        HStack(spacing: EonaSpacing.md) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(EonaColor.accent, in: .circle)
            PlaceLines(place: place)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Étape \(number), \(place.name)")
    }
}

/// L'arrivée, sous les étapes : fixe.
private struct ArrivalRow: View {
    let place: Place

    var body: some View {
        HStack(spacing: EonaSpacing.md) {
            Image(EonaSymbol.flag)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(EonaColor.accent)
                .frame(width: 26, height: 26)
                .background(EonaColor.accent.opacity(0.16), in: .circle)
            PlaceLines(place: place, caption: "Arrivée")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Arrivée, \(place.name)")
    }
}

private struct PlaceLines: View {
    let place: Place
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let caption {
                Text(caption)
                    .font(.xrCaption)
                    .foregroundStyle(EonaColor.textTertiary)
            }
            Text(place.name)
                .font(.xrBody)
                .foregroundStyle(EonaColor.textPrimary)
                .lineLimit(1)
            if !place.subtitle.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(place.subtitle)
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textTertiary)
                    .lineLimit(1)
            }
        }
    }
}
