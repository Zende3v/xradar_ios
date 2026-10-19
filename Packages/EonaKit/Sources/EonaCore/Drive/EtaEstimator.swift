import Foundation

/// The dynamic ETA (D2.1, D2.4): time left = the route's base time still ahead + the delays of the
/// jams still ahead, recomputed at each fix without a request. The base is the engine's time,
/// spread along the route by its steps' durations (a motorway kilometre is not a town's); with
/// the live source's time for the route (HERE's since 30/09, TomTom's before), that time less the
/// jams it lists, so the rush hour stays in it: the engine's alone is far too quick in towns.
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
        let delays = stretches.reduce(0.0) {
            $0 + delayAhead(from: $1.fromMeters * scale, to: $1.toMeters * scale, delay: $1.delaySeconds ?? 0, along: along)
        }
        guard let traffic, let travel = traffic.travelSeconds, travel > 0 else {
            return Double(route.durationSeconds) * baseShareLeft(route: route, routeMeters: routeMeters, along: along) + delays
        }
        // The live source timed the route from where the driver was ([startMeters]): its time less
        // the jams it lists there is the base of that rest, which shrinks along it as the engine's does.
        let start = min(max(traffic.startMeters * scale, 0), routeMeters)
        let listed = stretches
            .filter { $0.source == TrafficStretch.here || $0.source == TrafficStretch.tomtom }
            .reduce(0) { $0 + ($1.delaySeconds ?? 0) }
        let base = Double(max(travel - listed, 0))
        let shareAtStart = baseShareLeft(route: route, routeMeters: routeMeters, along: start)
        let share = shareAtStart > 0
            ? min(max(baseShareLeft(route: route, routeMeters: routeMeters, along: max(along, start)) / shareAtStart, 0), 1)
            : 0
        return base * share + delays
    }

    /// The part of the route's base time still ahead [along] metres into it: by its steps' own
    /// durations (their metres scaled to [routeMeters]), else by distance. A step with a time but
    /// no length (a ferry's wait) counts until the driver reaches it.
    public static func baseShareLeft(route: Route, routeMeters: Double, along: Double) -> Double {
        shareLeft(steps: route.steps, times: route.steps.map { Double($0.durationSeconds) }, routeMeters: routeMeters, along: along)
    }

    /// Temps moteur brut restant, avant correction EONA : référence de mesure, jamais affiché.
    /// Total brut de la route pondéré par les temps bruts des étapes, tous connus ; sinon par
    /// distance. Total brut inconnu (ancien backend) : nil, jamais le temps corrigé.
    public static func rawSecondsLeft(route: Route, routeMeters: Double, along: Double) -> Double? {
        guard let total = route.engineDurationSeconds, total > 0 else { return nil }
        let raw = route.steps.compactMap(\.engineDurationSeconds)
        let times = raw.count == route.steps.count ? raw.map { Double($0) } : []
        return Double(total) * shareLeft(steps: route.steps, times: times, routeMeters: routeMeters, along: along)
    }

    /// Part de [times] (un temps par étape) encore devant à [along] ; sans temps, par distance.
    private static func shareLeft(steps: [RouteStep], times: [Double], routeMeters: Double, along: Double) -> Double {
        guard routeMeters > 0 else { return 0 }
        let totalLength = steps.reduce(0.0) { $0 + Double($1.distanceMeters) }
        let totalTime = times.reduce(0, +)
        guard totalLength > 0, totalTime > 0, times.count == steps.count else { return min(max(1 - along / routeMeters, 0), 1) }
        let scale = routeMeters / totalLength
        var start = 0.0
        var left = 0.0
        for (step, time) in zip(steps, times) {
            let length = Double(step.distanceMeters) * scale
            let end = start + length
            if along <= start {
                left += time
            } else if along < end {
                left += time * (end - along) / length
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
