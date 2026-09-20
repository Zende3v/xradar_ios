/// One position reading, free of CoreLocation so the alert logic stays testable.
public struct LocationSample: Sendable, Hashable {
    public let latitude: Double
    public let longitude: Double
    /// Ground speed in metres/second, or nil if the fix has none.
    public let speedMps: Double?
    /// Heading in degrees (0..360, clockwise from north), or nil.
    public let bearingDeg: Double?
    /// Horizontal accuracy in metres, or nil.
    public let accuracyM: Double?
    /// Monotonic timestamp in millis.
    public let timeMs: Int

    public init(latitude: Double, longitude: Double, speedMps: Double?, bearingDeg: Double?, accuracyM: Double?, timeMs: Int) {
        self.latitude = latitude
        self.longitude = longitude
        self.speedMps = speedMps
        self.bearingDeg = bearingDeg
        self.accuracyM = accuracyM
        self.timeMs = timeMs
    }

    public var speedKmh: Double {
        (speedMps ?? 0) * 3.6
    }
}

/// Quality of the current GPS fix, surfaced to the driver.
public enum GpsSignal: Sendable, Hashable {
    /// No fix yet (acquiring).
    case searching
    /// Good, recent fix.
    case good
    /// Fix available but low accuracy.
    case weak
    /// Location turned off or no update for a while.
    case lost
}

/// Where the current speed sits relative to the active limit.
public enum SpeedStatus: Sendable, Hashable {
    case safe
    case caution
    case over

    /// Nil when no limit is known: the UI then uses a neutral color.
    public static func of(speedKmh: Int, limitKmh: Int?) -> SpeedStatus? {
        guard let limitKmh else { return nil }
        if speedKmh > limitKmh { return .over }
        if speedKmh >= limitKmh - 3 { return .caution }
        return .safe
    }
}
