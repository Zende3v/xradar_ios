import Foundation

/// A trip being driven, fed fix by fix: distance, top speed, standstills, the alerts met and the
/// route's estimate. Once the trip is over it makes the history record.
public struct TripRecorder: Sendable {
    /// Shorter trips are not kept.
    public static let minMeters = 500.0
    public static let minSeconds = 60.0
    /// Jumps outside this are GPS noise or a gap, not driving.
    static let stepMeters: ClosedRange<Double> = 1...250
    /// Slower than this is standing still (km/h).
    static let stoppedKmh = 3.0
    /// A standstill counts as a stop from this long: a red light, a queue at a standstill.
    static let minStopSeconds = 10.0
    /// An alert counts as met once it is this close.
    static let metMeters = 300

    public let startedAt: Date
    public private(set) var toLabel: String
    public private(set) var distanceMeters = 0.0
    private var topSpeedKmh = 0
    private var plannedSeconds: Int?
    private var stops = 0
    private var stoppedSeconds = 0.0
    private var stoppedSince: Date?
    /// Alerts met, by key, with their kind.
    private var met: [String: AlertType] = [:]

    /// How many alerts the trip has met, for the arrival card.
    public var alertsMet: Int { met.count }
    private var lastLat: Double?
    private var lastLon: Double?

    public init(toLabel: String, startedAt: Date = Date()) {
        self.toLabel = toLabel
        self.startedAt = startedAt
    }

    /// The destination changed on the way: the next route gives the new estimate.
    public mutating func retarget(_ label: String) {
        toLabel = label
        plannedSeconds = nil
    }

    /// The trip's route: the time already driven plus its estimate, once per destination.
    public mutating func plan(_ route: Route, now: Date = Date()) {
        guard plannedSeconds == nil else { return }
        plannedSeconds = Int(now.timeIntervalSince(startedAt).rounded()) + route.durationSeconds
    }

    public mutating func add(_ fix: LocationSample) {
        if let lastLat, let lastLon {
            let step = Geo.haversine(lat1: lastLat, lon1: lastLon, lat2: fix.latitude, lon2: fix.longitude)
            if Self.stepMeters.contains(step) { distanceMeters += step }
        }
        lastLat = fix.latitude
        lastLon = fix.longitude
        let kmh = fix.speedKmh
        topSpeedKmh = max(topSpeedKmh, Int(kmh.rounded()))

        let at = Date(millis: fix.timeMs)
        if kmh < Self.stoppedKmh {
            if stoppedSince == nil { stoppedSince = at }
        } else if let since = stoppedSince {
            stoppedSince = nil
            let still = at.timeIntervalSince(since)
            if still >= Self.minStopSeconds {
                stops += 1
                stoppedSeconds += still
            }
        }
    }

    /// The alerts on the HUD now: each one reached counts once.
    public mutating func meet(_ alerts: [RoadAlert]) {
        for alert in alerts where alert.distanceMeters <= Self.metMeters && met[alert.key] == nil {
            met[alert.key] = alert.type
        }
    }

    /// The history record, or nil for a trip too short to keep. A standstill still running at the
    /// end (parked at the destination) is not a stop.
    public func record(id: String, now: Date = Date()) -> TripRecord? {
        let duration = now.timeIntervalSince(startedAt)
        guard distanceMeters >= Self.minMeters, duration >= Self.minSeconds else { return nil }
        var events: [AlertType: Int] = [:]
        for type in met.values {
            events[type, default: 0] += 1
        }
        return TripRecord(
            id: id,
            startedAt: Int(startedAt.timeIntervalSince1970 * 1000),
            fromLabel: "Ma position",
            toLabel: toLabel,
            distanceMeters: Int(distanceMeters.rounded()),
            durationSeconds: Int(duration),
            alertsCount: met.count,
            topSpeedKmh: topSpeedKmh,
            plannedSeconds: plannedSeconds,
            stops: stops,
            stoppedSeconds: Int(stoppedSeconds.rounded()),
            events: events
        )
    }
}
