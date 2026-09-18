import Foundation

/// How slow a stretch of the route is, as TomTom reports it; the raw value is the backend's name.
public enum TrafficLevel: String, Sendable, Hashable, CaseIterable {
    /// Slower than usual.
    case slow
    /// A traffic jam.
    case jam
    /// A heavy jam: a lot of time lost.
    case heavy
    /// The road is closed.
    case closed
}

/// One slowed stretch, in metres along the route polyline the backend received.
public struct TrafficStretch: Sendable, Hashable {
    public let fromMeters: Double
    public let toMeters: Double
    public let level: TrafficLevel

    public init(fromMeters: Double, toMeters: Double, level: TrafficLevel) {
        self.fromMeters = fromMeters
        self.toMeters = toMeters
        self.level = level
    }
}

/// The traffic on the route being followed: its slowed stretches, measured along a polyline
/// [totalMeters] long (the backend's measure of the route the app sent). Empty: a clear road.
public struct RouteTraffic: Sendable, Hashable {
    public let totalMeters: Double
    public let stretches: [TrafficStretch]

    public init(totalMeters: Double, stretches: [TrafficStretch]) {
        self.totalMeters = totalMeters
        self.stretches = stretches
    }
}
