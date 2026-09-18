import Foundation

/// A crawl on a road meant to be fluid, as the app saw it: sent (anonymously) as a probe.
public struct Slowdown: Sendable, Hashable {
    public let lat: Double
    public let lon: Double
    /// Course of the traffic concerned (the driver's).
    public let bearingDeg: Double
    /// The median speed over the window.
    public let speedKmh: Int
    public let limitKmh: Int

    public init(lat: Double, lon: Double, bearingDeg: Double, speedKmh: Int, limitKmh: Int) {
        self.lat = lat
        self.lon = lon
        self.bearingDeg = bearingDeg
        self.speedKmh = speedKmh
        self.limitKmh = limitKmh
    }
}

/// "Ralentissement du trafic ?": notices a slowdown from the fixes the app already gets, with no
/// timer and no extra GPS. Only on roads limited to [minLimitKmh] or more (the road's own limit,
/// not a radar's), where lights, crossings and parking do not explain a slow pace. A slowdown
/// is a whole [windowSeconds] at a median speed under [maxSpeedRatio] of the limit, still moving
/// ([minMovedMeters] at least: not parked), with a precise position. After one, nothing for
/// [cooldownSeconds]. The backend gets the same rules (probeMinLimitKmh, probeMaxSpeedRatio).
public struct SlowdownDetector: Sendable {
    public static let minLimitKmh = 70
    public static let windowSeconds = 90.0
    /// The window must be this full: a fix every 3 s on average at least.
    static let minFixes = 30
    public static let maxSpeedRatio = 0.5
    /// "Still slow now": the last seconds of the window.
    static let nowSeconds = 20.0
    public static let minMovedMeters = 150.0
    public static let maxAccuracyMeters = 30.0
    public static let cooldownSeconds = 300.0

    private struct Fix: Sendable {
        let at: Double
        let lat: Double
        let lon: Double
        let kmh: Double
        let bearing: Double?
    }

    private var fixes: [Fix] = []
    private var lastSlowdownAt: Double?

    public init() {}

    /// One fix: its filtered [speedKmh], and the limit where it is ([limitFromRoad] false for a
    /// radar's limit). [paused] (the trip's first or last metres) starts the window again.
    public mutating func update(sample: LocationSample, speedKmh: Int, limitKmh: Int?, limitFromRoad: Bool, paused: Bool) -> Slowdown? {
        let now = Double(sample.timeMs) / 1000
        guard let limit = limitKmh, limitFromRoad, limit >= Self.minLimitKmh, !paused else {
            fixes.removeAll()
            return nil
        }
        if let last = lastSlowdownAt, now - last < Self.cooldownSeconds { return nil }
        // A poor fix is left out, without breaking the window.
        if let accuracy = sample.accuracyM, accuracy > Self.maxAccuracyMeters { return nil }
        fixes.append(Fix(at: now, lat: sample.latitude, lon: sample.longitude, kmh: Double(speedKmh), bearing: sample.bearingDeg))
        fixes.removeAll { now - $0.at > Self.windowSeconds }
        guard let first = fixes.first, now - first.at >= Self.windowSeconds - 5, fixes.count >= Self.minFixes else { return nil }

        // Slow over the window, and still slow now: a jam already left behind is not asked about.
        let slow = Self.maxSpeedRatio * Double(limit)
        let median = Self.median(fixes.map(\.kmh))
        guard median < slow, Self.median(fixes.filter { now - $0.at <= Self.nowSeconds }.map(\.kmh)) < slow else { return nil }
        var moved = 0.0
        for (a, b) in zip(fixes, fixes.dropFirst()) {
            moved += Geo.haversine(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon)
        }
        guard moved >= Self.minMovedMeters, let last = fixes.last else { return nil }
        // The way the car goes: its last course, else the way it moved over the window.
        let bearing = last.bearing ?? Geo.bearing(lat1: first.lat, lon1: first.lon, lat2: last.lat, lon2: last.lon)
        lastSlowdownAt = now
        fixes.removeAll()
        return Slowdown(lat: last.lat, lon: last.lon, bearingDeg: bearing, speedKmh: Int(median.rounded()), limitKmh: limit)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }
}
