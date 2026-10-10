import SwiftUI
import EonaCore
import EonaData

/// Search, full screen over the HUD in Liquid Glass (the map and the HUD show through, light or
/// dark with the app's theme), like the Android search route: an address (Base Adresse
/// Nationale, as the driver types), a category of services around, home, work, favourite trips
/// and recents. A pick sets the trip's destination (and closes), its simulated start, or a saved
/// address. Ouverte pour une étape : le choix devient une étape du trajet.
struct SearchScreen: View {
    let services: AppServices
    /// Ouverte depuis « Ajouter une étape ».
    let addingStop: Bool
    let onClose: () -> Void

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var loading = false
    @State private var target: PickTarget
    @State private var category: PlaceCategory?
    @State private var categoryPlaces: [Place] = []
    @State private var categoryLoading = false
    @State private var categoryFailed = false
    @State private var categoryAttempt = 0
    @State private var fuelRadiusM = 10_000

    private static let minQuery = 3
    /// How far the glass reaches past each edge of the screen.
    private static let glassBleed: CGFloat = 40

    init(services: AppServices, addingStop: Bool = false, onClose: @escaping () -> Void) {
        self.services = services
        self.addingStop = addingStop
        self.onClose = onClose
        _target = State(initialValue: addingStop ? .stop : .destination)
    }

    /// Ce que vise la recherche hors départ et adresses enregistrées.
    private var baseTarget: PickTarget {
        addingStop ? .stop : .destination
    }

    /// Destination en cours ou proposée : un résultat peut aussi devenir une étape (« + »).
    private var quickStop: ((Place) -> Void)? {
        let trip = services.activeTrip
        guard target == .destination, trip.destination != nil || trip.proposal != nil, trip.stops.count < ActiveTripStore.maxStops else {
            return nil
        }
        return { place in
            trip.addStop(place)
            onClose()
        }
    }

    var body: some View {
        let start = services.activeTrip.start
        let hasFix = services.location.location != nil
        let fuel = services.preferences.settings.preferredFuel
        let nearestOnly = services.preferences.settings.fuelNearestOnly
        let cashOnly = services.preferences.settings.fuelCashOnly

        VStack(spacing: 0) {
            // Departure and arrival, one above the other: the departure is always in sight,
            // and a tap on it is all it takes to change it.
            HStack(alignment: .top, spacing: EonaSpacing.sm) {
                RouteStopsCard(
                    start: start,
                    query: $query,
                    editingStart: target == .start,
                    arrivalPrompt: target == .start ? baseTarget.prompt : target.prompt,
                    onEditStart: {
                        target = .start
                        query = ""
                        category = nil
                    },
                    onEditArrival: {
                        target = baseTarget
                        query = ""
                    },
                    onResetStart: { services.activeTrip.setStart(nil) },
                    startEditable: !addingStop
                )
                Button("Annuler", action: onClose)
                    .font(.xrLabel)
                    .foregroundStyle(EonaColor.accent)
                    .buttonStyle(.borderless)
                    .frame(height: 46)
            }
            .padding(.horizontal, EonaSpacing.lg)
            .padding(.top, EonaSpacing.sm)
            .padding(.bottom, EonaSpacing.xs)

            CategoryRow(selected: category) { picked in
                // After a failed search, the same category again means "try again".
                if category == picked && categoryFailed {
                    categoryAttempt += 1
                } else {
                    category = category == picked ? nil : picked
                }
                categoryPlaces = []
                categoryLoading = category != nil
                categoryFailed = false
            }

            if category == .fuel {
                FuelSearchFilters(
                    selected: fuel,
                    nearestOnly: nearestOnly,
                    cashOnly: cashOnly,
                    radiusM: fuelRadiusM,
                    onSelect: { picked in
                        services.preferences.updateSettings { $0.preferredFuel = picked }
                    },
                    onSort: { nearest in services.preferences.updateSettings { $0.fuelNearestOnly = nearest } },
                    onCash: {
                        categoryLoading = true
                        services.preferences.updateSettings { $0.fuelCashOnly.toggle() }
                    },
                    onRadius: changeFuelRadius
                )
            }

            content(
                waitingForPosition: start == nil && !hasFix,
                fuel: category == .fuel ? fuel : nil,
                fuelOrder: nearestOnly ? .nearest : .price,
                cashOnly: cashOnly
            )
            .frame(maxHeight: .infinity)
        }
        .background {
            // Taken by taps everywhere, the HUD under it included. The glass is drawn larger
            // than the screen: its rim falls outside, and no edge of the map shows around it.
            GeometryReader { proxy in
                Color.clear
                    .frame(width: proxy.size.width + Self.glassBleed * 2, height: proxy.size.height + Self.glassBleed * 2)
                    .glassEffect(.regular.tint(EonaColor.canvas.opacity(0.35)), in: .rect)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .contentShape(.rect)
            .ignoresSafeArea()
        }
        .task(id: query) {
            await geocode()
        }
        .task(id: CategorySearch(category: category, startId: start?.id, hasFix: hasFix, attempt: categoryAttempt,
                                 radiusM: category == .fuel ? fuelRadiusM : nil,
                                 cashOnly: category == .fuel && cashOnly)) {
            await searchCategory(from: start)
        }
    }

    @ViewBuilder
    private func content(waitingForPosition: Bool, fuel: FuelType?, fuelOrder: FuelStationOrder, cashOnly: Bool) -> some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.minQuery {
            if loading {
                EonaLoadingState(label: "Recherche…")
            } else if results.isEmpty {
                EonaMessageState(icon: .symbol(.search), title: "Aucun résultat", message: "Rien ne correspond à « \(query) ».")
            } else {
                ResultList(results: results, onPick: { pick($0) }, onAddStop: quickStop)
            }
        } else if let category {
            if categoryLoading {
                EonaLoadingState(label: waitingForPosition ? "En attente de ta position…" : "Recherche autour de toi…")
            } else if categoryFailed {
                if category == .fuel {
                    VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                        Text("Stations indisponibles").font(.xrBodyStrong)
                        EonaButton(title: "Réessayer", variant: .secondary) {
                            categoryLoading = true
                            categoryAttempt += 1
                        }
                    }
                    .padding(EonaSpacing.lg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    EonaMessageState(
                        icon: .symbol(.warning), title: "Recherche indisponible",
                        message: "Vérifie ta connexion.", primaryLabel: "Réessayer",
                        onPrimary: { categoryAttempt += 1 }
                    )
                }
            } else if categoryPlaces.isEmpty && category != .fuel {
                EonaMessageState(icon: .symbol(.search), title: "Rien trouvé", message: "Aucun résultat pour « \(category.label) » dans les environs.")
            } else {
                NearbyList(
                    places: categoryPlaces, category: category, fuel: fuel,
                    fuelOrder: fuelOrder, cashOnly: category == .fuel && cashOnly,
                    radiusM: fuelRadiusM,
                    onRadius: changeFuelRadius,
                    onAllPayments: {
                        categoryLoading = true
                        services.preferences.updateSettings { $0.fuelCashOnly = false }
                    },
                    onPick: { pick($0) }, onAddStop: quickStop
                )
                .id("\(category.rawValue)-\(fuel?.rawValue ?? "")-\(fuelOrder)-\(cashOnly)")
            }
        } else {
            // One block: the frame given to the content must not stretch the first row.
            VStack(spacing: 0) {
                if target == .start {
                    UseMyPositionRow {
                        services.activeTrip.setStart(nil)
                        target = baseTarget
                        query = ""
                    }
                }
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
                        // Étape demandée : arrivée du favori ajoutée, départ inchangé.
                        if addingStop {
                            pick(trip.to)
                            return
                        }
                        services.activeTrip.setStart(trip.from)
                        // Choix d'itinéraire d'abord (Rapide, Éco).
                        services.activeTrip.propose(trip.to)
                        onClose()
                    }
                )
            }
        }
    }

    private func changeFuelRadius(_ radius: Int) {
        guard radius != fuelRadiusM else { return }
        categoryLoading = true
        fuelRadiusM = radius
    }

    /// Live search, debounced: the backend merges places and addresses.
    private func geocode() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= Self.minQuery else {
            results = []
            loading = false
            return
        }
        loading = true
        // Court : les suggestions suivent la frappe sans bombarder le serveur.
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        let around = services.location.location.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) }
        let found = await SearchAPI(client: services.client).search(text, around: around, token: services.account.token)
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
        let found = await PlacesAPI(client: services.client).near(
            category: category, lat: origin.lat, lon: origin.lon,
            radiusM: category == .fuel ? fuelRadiusM : nil,
            cashOnly: category == .fuel && services.preferences.settings.fuelCashOnly
        )
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
            // Choix d'itinéraire d'abord (Rapide, Éco) ; trajet lancé au choix.
            services.activeTrip.propose(place)
            onClose()
        case .stop:
            services.activeTrip.addStop(place)
            onClose()
        case .start:
            services.activeTrip.setStart(place)
            target = baseTarget
            query = ""
            category = nil
        case .home:
            services.savedPlaces.setHome(place)
            target = baseTarget
            query = ""
        case .work:
            services.savedPlaces.setWork(place)
            target = baseTarget
            query = ""
        }
    }
}

/// What the next pick sets: the trip's destination, a stop, its start, or a saved address.
private enum PickTarget {
    case destination
    case stop
    case start
    case home
    case work

    var prompt: String {
        switch self {
        case .destination: "Où allez-vous ?"
        case .stop: "Ajouter une étape"
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
    let radiusM: Int?
    let cashOnly: Bool
}
