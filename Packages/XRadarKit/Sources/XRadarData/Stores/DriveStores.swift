import Foundation
import Observation
import XRadarCore

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

    init(_ trip: TripRecord) {
        id = trip.id
        startedAt = trip.startedAt
        fromLabel = trip.fromLabel
        toLabel = trip.toLabel
        distanceMeters = trip.distanceMeters
        durationSeconds = trip.durationSeconds
        alertsCount = trip.alertsCount
        topSpeedKmh = trip.topSpeedKmh
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
            topSpeedKmh: topSpeedKmh
        )
    }
}

/// The active navigation: the chosen destination, an optional simulated start, and the route.
@MainActor
@Observable
public final class ActiveTripStore {
    public private(set) var destination: Place?
    /// Simulated departure. Nil = the driver's own position, the normal case.
    public private(set) var start: Place?
    public private(set) var route: Route?

    public init() {}

    public func setDestination(_ place: Place?) {
        destination = place
        if place == nil { route = nil }
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
