import Foundation
import Observation
import EonaCore

/// Aggregate of the local trips, for the profile screen.
public struct TripStats: Sendable, Hashable {
    public let trips: Int
    public let kilometers: Int
    public let alerts: Int

    public init(trips: Int, kilometers: Int, alerts: Int) {
        self.trips = trips
        self.kilometers = kilometers
        self.alerts = alerts
    }
}

/// Local trip history (UserDefaults + JSON), newest first. Guests keep everything here only:
/// deleting the app loses it, by design.
@MainActor
@Observable
public final class TripHistoryStore {
    public static let limit = 200

    public private(set) var trips: [TripRecord]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        trips = Self.newestFirst((defaults.decoded([StoredTrip].self, forKey: Keys.list) ?? []).map(\.trip))
    }

    public func add(_ trip: TripRecord) {
        let updated = Array(([trip] + trips).prefix(Self.limit))
        defaults.encode(updated.map { StoredTrip($0) }, forKey: Keys.list)
        trips = Self.newestFirst(updated)
    }

    /// The group trip ended: its ranking joins the trip already saved. Nothing else moves.
    public func attach(group: TripGroupResult, to tripId: String) {
        guard let index = trips.firstIndex(where: { $0.id == tripId }) else { return }
        var updated = trips
        updated[index] = trips[index].with(group: group)
        defaults.encode(updated.map { StoredTrip($0) }, forKey: Keys.list)
        trips = updated
    }

    /// The account is deleted: its trips go with it.
    public func removeAll() {
        defaults.removeObject(forKey: Keys.list)
        trips = []
    }

    public var stats: TripStats {
        TripStats(
            trips: trips.count,
            kilometers: trips.reduce(0) { $0 + $1.distanceMeters } / 1000,
            alerts: trips.reduce(0) { $0 + $1.alertsCount }
        )
    }

    private static func newestFirst(_ trips: [TripRecord]) -> [TripRecord] {
        trips.sorted { $0.startedAt > $1.startedAt }
    }

    private enum Keys {
        static let list = "xr_trips.list"
    }
}

struct StoredTrip: Codable {
    let id: String
    let startedAt: Int
    let fromLabel: String
    let toLabel: String
    let distanceMeters: Int
    let durationSeconds: Int
    let alertsCount: Int
    let topSpeedKmh: Int
    // Absent from trips saved before these details were recorded.
    let plannedSeconds: Int?
    let stops: Int?
    let stoppedSeconds: Int?
    let events: [String: Int]?
    // Absent from a trip driven alone.
    let group: TripGroupResult?
    // Absent from trips saved before the ETA and route measures.
    let measure: TripMeasure?

    init(_ trip: TripRecord) {
        id = trip.id
        startedAt = trip.startedAt
        fromLabel = trip.fromLabel
        toLabel = trip.toLabel
        distanceMeters = trip.distanceMeters
        durationSeconds = trip.durationSeconds
        alertsCount = trip.alertsCount
        topSpeedKmh = trip.topSpeedKmh
        plannedSeconds = trip.plannedSeconds
        stops = trip.stops
        stoppedSeconds = trip.stoppedSeconds
        events = AccountAPI.wireEvents(trip.events)
        group = trip.group
        measure = trip.measure
    }

    var trip: TripRecord {
        TripRecord(
            id: id,
            startedAt: startedAt,
            fromLabel: fromLabel,
            toLabel: toLabel,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            alertsCount: alertsCount,
            topSpeedKmh: topSpeedKmh,
            plannedSeconds: plannedSeconds,
            stops: stops ?? 0,
            stoppedSeconds: stoppedSeconds ?? 0,
            events: Dictionary(uniqueKeysWithValues: (events ?? [:]).compactMap { name, count in
                AlertType(wireName: name).map { ($0, count) }
            }),
            group: group,
            measure: measure
        )
    }
}

/// The active navigation: the chosen destination, an optional simulated start, and the route.
/// [proposal] : destination choisie, en attente du choix d'itinéraire (Rapide, Éco).
@MainActor
@Observable
public final class ActiveTripStore {
    public private(set) var destination: Place?
    public private(set) var proposal: Place?
    /// Étapes restantes avant la destination, dans l'ordre ; retirées une à une en route.
    public private(set) var stops: [Place] = []

    /// Étapes au plus, comme le backend.
    public static let maxStops = 10
    /// Simulated departure. Nil = the driver's own position, the normal case.
    public private(set) var start: Place?
    public private(set) var route: Route?

    public init() {}

    public func setDestination(_ place: Place?) {
        destination = place
        if place == nil {
            route = nil
            stops = []
        }
    }

    /// Une étape de plus, en dernier avant la destination. Liste pleine, étape déjà prévue ou
    /// destination elle-même : rien.
    public func addStop(_ place: Place) {
        guard stops.count < Self.maxStops,
              !stops.contains(where: { $0.id == place.id }),
              place.id != destination?.id, place.id != proposal?.id
        else { return }
        stops.append(place)
    }

    /// Étapes réordonnées ou retirées par le conducteur.
    public func setStops(_ places: [Place]) {
        stops = Array(places.prefix(Self.maxStops))
    }

    /// Première étape atteinte : retirée.
    public func stopReached() {
        if !stops.isEmpty { stops.removeFirst() }
    }

    /// Destination choisie : choix d'itinéraire d'abord, trajet ensuite. Nil : choix refermé.
    public func propose(_ place: Place?) {
        proposal = place
    }

    public func setStart(_ place: Place?) {
        start = place
    }

    public func setRoute(_ newRoute: Route?) {
        route = newRoute
    }

    public func clear() {
        destination = nil
        route = nil
        start = nil
        stops = []
    }
}

/// Whether the app may read the position.
public enum LocationAuthorization: Sendable, Hashable {
    case notDetermined
    case denied
    case granted
}

/// The latest position and the quality of the fix. The location tracker writes; screens read.
@MainActor
@Observable
public final class LocationState {
    /// A fix at least this precise is a good signal.
    public static let goodAccuracyMeters = 30.0

    public private(set) var location: LocationSample?
    public private(set) var signal: GpsSignal = .searching
    public private(set) var authorization: LocationAuthorization = .notDetermined

    public init() {}

    public func update(_ sample: LocationSample) {
        location = sample
        let precise = sample.accuracyM.map { $0 <= Self.goodAccuracyMeters } ?? true
        signal = precise ? .good : .weak
    }

    public func setLost() {
        signal = .lost
    }

    public func reset() {
        location = nil
        signal = .searching
    }

    public func setAuthorization(_ value: LocationAuthorization) {
        authorization = value
    }
}
