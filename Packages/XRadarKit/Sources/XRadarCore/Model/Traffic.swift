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

/// The traffic on the route being followed: its slowed stretches (TomTom's, and the drivers' own
/// jams where they cost more), measured along a polyline [totalMeters] long (the backend's
/// measure of the route the app sent). Empty: a clear road. [worthChecking]: the backend says a
/// faster route may exist ahead of the driver ("Éviter les bouchons" then asks for one).
public struct RouteTraffic: Sendable, Hashable {
    public let totalMeters: Double
    public let stretches: [TrafficStretch]
    public let worthChecking: Bool

    public init(totalMeters: Double, stretches: [TrafficStretch], worthChecking: Bool = false) {
        self.totalMeters = totalMeters
        self.stretches = stretches
        self.worthChecking = worthChecking
    }

    /// Whether a slowed stretch covers [meters] along the route ([routeMeters], the app's own
    /// length of it: the backend's measure is scaled to it).
    public func slowed(at meters: Double, routeMeters: Double) -> Bool {
        let scale = totalMeters > 0 ? routeMeters / totalMeters : 1
        return stretches.contains { $0.fromMeters * scale <= meters && meters <= $0.toMeters * scale }
    }
}

/// A faster way to the destination around the traffic, and the time it saves; or the way
/// around a closed road ([closed]), whatever it costs.
public struct FasterRoute: Sendable, Hashable {
    public let route: Route
    public let gainSeconds: Int
    public let closed: Bool

    public init(route: Route, gainSeconds: Int, closed: Bool = false) {
        self.route = route
        self.gainSeconds = gainSeconds
        self.closed = closed
    }
}
