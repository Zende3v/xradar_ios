import SwiftUI
import XRadarCore
import XRadarData

/// Search, full screen over the HUD in Liquid Glass (the map and the HUD show through, light or
/// dark with the app's theme), like the Android search route: an address (Base Adresse
/// Nationale, as the driver types), a category of services around, home, work, favourite trips
/// and recents. A pick sets the trip's destination (and closes), its simulated start, or a saved
/// address.
struct SearchScreen: View {
    let services: AppServices
    let onClose: () -> Void

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var loading = false
    @State private var target = PickTarget.destination
    @State private var category: PlaceCategory?
    @State private var categoryPlaces: [Place] = []
    @State private var categoryLoading = false
    @State private var categoryFailed = false
    @State private var categoryAttempt = 0

    private static let minQuery = 3

    var body: some View {
        let start = services.activeTrip.start
        let hasFix = services.location.location != nil
        let fuel = services.preferences.settings.preferredFuel
        let nearestOnly = services.preferences.settings.fuelNearestOnly
        // Official prices ride on the stations the search already found. When none of them has
        // any (backend without prices yet), the list stays as it was.
        let showPrices = category == .fuel
            && (categoryLoading || categoryPlaces.isEmpty || categoryPlaces.contains { $0.fuel != nil })

        VStack(spacing: 0) {
            HStack(spacing: XRadarSpacing.sm) {
                // The keyboard waits for a tap in the field (Arthur's choice).
                XRadarSearchField(text: $query, placeholder: target.prompt)
                Button("Annuler", action: onClose)
                    .font(.xrLabel)
                    .foregroundStyle(XRadarColor.accent)
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, XRadarSpacing.lg)
            .padding(.vertical, XRadarSpacing.sm)

            StartRow(
                start: start,
                onEdit: {
                    target = .start
                    query = ""
                },
                onClear: { services.activeTrip.setStart(nil) }
            )

            CategoryRow(selected: category) { picked in
                // After a failed search, the same category again means "try again".
                if category == picked && categoryFailed {
                    categoryAttempt += 1
                } else {
                    category = category == picked ? nil : picked
                }
                categoryPlaces = []
            }

            if showPrices {
                FuelTypeRow(
                    selected: fuel,
                    nearestOnly: nearestOnly,
                    onSelect: { picked in
                        services.preferences.updateSettings {
                            $0.preferredFuel = picked
                            $0.fuelNearestOnly = false
                        }
                    },
                    onNearestOnly: { services.preferences.updateSettings { $0.fuelNearestOnly = true } }
                )
            }

            content(
                waitingForPosition: start == nil && !hasFix,
                fuel: showPrices && !nearestOnly ? fuel : nil,
                openOnly: category == .fuel && nearestOnly
            )
            .frame(maxHeight: .infinity)
        }
        .background {
            // Taken by taps everywhere, the HUD under it included.
            Color.clear
                .contentShape(.rect)
                .glassEffect(.regular.tint(XRadarColor.canvas.opacity(0.35)), in: .rect)
                .ignoresSafeArea()
        }
        .task(id: query) {
            await geocode()
        }
        .task(id: CategorySearch(category: category, startId: start?.id, hasFix: hasFix, attempt: categoryAttempt)) {
            await searchCategory(from: start)
        }
    }

    @ViewBuilder
    private func content(waitingForPosition: Bool, fuel: FuelType?, openOnly: Bool) -> some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.minQuery {
            if loading {
                XRadarLoadingState(label: "Recherche…")
            } else if results.isEmpty {
                XRadarMessageState(icon: .symbol(.search), title: "Aucun résultat", message: "Rien ne correspond à « \(query) ».")
            } else {
                ResultList(results: results, onPick: { pick($0) })
            }
        } else if let category {
            if categoryLoading {
                XRadarLoadingState(label: waitingForPosition ? "En attente de ta position…" : "Recherche autour de toi…")
            } else if categoryFailed {
                XRadarMessageState(
                    icon: .symbol(.warning),
                    title: "Recherche indisponible",
                    message: "Le serveur ne répond pas. Vérifie ta connexion, puis touche à nouveau « \(category.label) »."
                )
            } else if categoryPlaces.isEmpty {
                XRadarMessageState(icon: .symbol(.search), title: "Rien trouvé", message: "Aucun résultat pour « \(category.label) » dans les environs.")
            } else {
                NearbyList(places: categoryPlaces, category: category, fuel: fuel, openOnly: openOnly, onPick: { pick($0) })
                    // Another fuel or category is another list: it starts from the top.
                    .id("\(category.rawValue)-\(fuel?.rawValue ?? "")-\(openOnly)")
            }
        } else {
            SavedPlacesList(
                saved: services.savedPlaces,
                recents: services.recents,
                showsRecents: services.preferences.settings.tripSuggestions,
                start: services.activeTrip.start,
                onPick: { pick($0) },
                onSetHome: {
                    target = .home
                    query = ""
                },
                onSetWork: {
                    target = .work
                    query = ""
                },
                onStartFavorite: { trip in
                    services.activeTrip.setStart(trip.from)
                    services.activeTrip.setDestination(trip.to)
                    onClose()
                }
            )
        }
    }

    /// Live geocoding, debounced.
    private func geocode() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= Self.minQuery else {
            results = []
            loading = false
            return
        }
        loading = true
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let found = (try? await GeocodingAPI().search(text)) ?? []
        guard !Task.isCancelled else { return }
        results = found
        loading = false
    }

    /// The nearest places of the chosen category, searched from the trip's start, else from the
    /// driver's position as soon as there is one.
    private func searchCategory(from start: Place?) async {
        guard let category else { return }
        categoryFailed = false
        let origin = start.map { GeoPoint(lat: $0.lat, lon: $0.lon) }
            ?? services.location.location.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) }
        guard let origin else {
            categoryPlaces = []
            categoryLoading = true
            return
        }
        categoryLoading = true
        let found = await PlacesAPI(client: services.client).near(category: category, lat: origin.lat, lon: origin.lon)
        guard !Task.isCancelled else { return }
        categoryPlaces = found ?? []
        categoryFailed = found == nil
        categoryLoading = false
    }

    private func pick(_ place: Place) {
        switch target {
        case .destination:
            // "Suggestions de trajets" (Confidentialité): only then is the destination kept.
            if services.preferences.settings.tripSuggestions {
                services.recents.add(place)
            }
            services.activeTrip.setDestination(place)
            onClose()
        case .start:
            services.activeTrip.setStart(place)
            target = .destination
            query = ""
            category = nil
        case .home:
            services.savedPlaces.setHome(place)
            target = .destination
            query = ""
        case .work:
            services.savedPlaces.setWork(place)
            target = .destination
            query = ""
        }
    }
}

/// What the next pick sets: the trip's destination, its start, or a saved address.
private enum PickTarget {
    case destination
    case start
    case home
    case work

    var prompt: String {
        switch self {
        case .destination: "Où allez-vous ?"
        case .start: "Point de départ"
        case .home: "Adresse de la maison"
        case .work: "Adresse du travail"
        }
    }
}

/// What restarts the nearby search.
nonisolated private struct CategorySearch: Equatable {
    let category: PlaceCategory?
    let startId: String?
    let hasFix: Bool
    let attempt: Int
}
