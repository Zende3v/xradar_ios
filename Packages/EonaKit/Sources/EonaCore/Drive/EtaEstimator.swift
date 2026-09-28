import Foundation

/// The dynamic ETA (D2.1, D2.4): time left = the route's base time still ahead + the delays of the
/// jams still ahead, recomputed at each fix without a request. The base is the engine's time,
/// spread along the route by its steps' durations (a motorway kilometre is not a town's); with
/// TomTom's time for the route, that time less the jams TomTom lists, so the rush hour stays in it.
/// A jam counts whole ahead of the driver, pro rata once inside it, not at all behind. The HUD,
/// the shared trip, the group and the trip's measures all read this one. Same rules as Android.
public enum EtaEstimator {
    /// How the trips record their ETA (D2.5): "dynamic", "proportional" before.
    public static let mode = "dynamic"

    /// Seconds left on [route] for a driver [alongMeters] along it, [routeMeters] being the app's
    /// own length of it; [traffic] measured on that route (its metres scaled to [routeMeters]).
    public static func secondsLeft(route: Route, routeMeters: Double, alongMeters: Double, traffic: RouteTraffic? = nil) -> Double {
        guard routeMeters > 0 else { return 0 }
        let along = min(max(alongMeters, 0), routeMeters)
        let stretches = traffic?.stretches ?? []
        let scale = traffic.map { $0.totalMeters > 0 ? routeMeters / $0.totalMeters : 1 } ?? 1
        let listed = stretches.filter { $0.source == TrafficStretch.tomtom }.reduce(0) { $0 + ($1.delaySeconds ?? 0) }
        let baseTotal: Double
        if let travel = traffic?.travelSeconds, travel > 0 {
            baseTotal = Double(max(travel - listed, 0))
        } else {
            baseTotal = Double(route.durationSeconds)
        }
        let delays = stretches.reduce(0.0) {
            $0 + delayAhead(from: $1.fromMeters * scale, to: $1.toMeters * scale, delay: $1.delaySeconds ?? 0, along: along)
        }
        return baseTotal * baseShareLeft(route: route, routeMeters: routeMeters, along: along) + delays
    }

    /// The part of the route's base time still ahead [along] metres into it: by its steps' own
    /// durations (their metres scaled to [routeMeters]), else by distance. A step with a time but
    /// no length (a ferry's wait) counts until the driver reaches it.
    public static func baseShareLeft(route: Route, routeMeters: Double, along: Double) -> Double {
        guard routeMeters > 0 else { return 0 }
        let totalLength = route.steps.reduce(0.0) { $0 + Double($1.distanceMeters) }
        let totalTime = route.steps.reduce(0.0) { $0 + Double($1.durationSeconds) }
        guard totalLength > 0, totalTime > 0 else { return min(max(1 - along / routeMeters, 0), 1) }
        let scale = routeMeters / totalLength
        var start = 0.0
        var left = 0.0
        for step in route.steps {
            let length = Double(step.distanceMeters) * scale
            let end = start + length
            if along <= start {
                left += Double(step.durationSeconds)
            } else if along < end {
                left += Double(step.durationSeconds) * (end - along) / length
            }
            start = end
        }
        return min(max(left / totalTime, 0), 1)
    }

    /// What a jam from [from] to [to] metres, costing [delay] s, still costs a driver at [along].
    private static func delayAhead(from: Double, to: Double, delay: Int, along: Double) -> Double {
        if delay <= 0 || to <= along { return 0 }
        if from >= along || to <= from { return Double(delay) }
        return Double(delay) * (to - along) / (to - from)
    }
}

/// The arrival shown: it moves only once the ETA moved by a minute or more (D2.4).
public struct ArrivalClock: Sendable {
    static let moveSeconds = 60.0
    private var shownAt: Date?

    public init() {}

    public mutating func shown(_ arrival: Date) -> Date {
        if let current = shownAt, abs(arrival.timeIntervalSince(current)) < Self.moveSeconds { return current }
        shownAt = arrival
        return arrival
    }

    public mutating func reset() {
        shownAt = nil
    }
}
