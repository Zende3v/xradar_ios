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

/// One slowed stretch, in metres along the route polyline the backend received, and the time
/// lost on it (nil when TomTom does not say).
public struct TrafficStretch: Sendable, Hashable {
    public let fromMeters: Double
    public let toMeters: Double
    public let level: TrafficLevel
    public let delaySeconds: Int?

    public init(fromMeters: Double, toMeters: Double, level: TrafficLevel, delaySeconds: Int? = nil) {
        self.fromMeters = fromMeters
        self.toMeters = toMeters
        self.level = level
        self.delaySeconds = delaySeconds
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

    /// Time lost to traffic beyond [meters] along the route, and whether a closed road lies there.
    /// [routeMeters] is the app's own length of the route: the backend's measure is scaled to it.
    public func ahead(of meters: Double, routeMeters: Double) -> (lostSeconds: Int, closed: Bool) {
        let scale = totalMeters > 0 ? routeMeters / totalMeters : 1
        let coming = stretches.filter { $0.toMeters * scale > meters }
        return (coming.reduce(0) { $0 + ($1.delaySeconds ?? 0) }, coming.contains { $0.level == .closed })
    }
}

/// A faster way to the destination around the traffic, and the time it saves.
public struct FasterRoute: Sendable, Hashable {
    public let route: Route
    public let gainSeconds: Int

    public init(route: Route, gainSeconds: Int) {
        self.route = route
        self.gainSeconds = gainSeconds
    }
}
