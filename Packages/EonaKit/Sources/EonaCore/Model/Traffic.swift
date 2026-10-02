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

/// One slowed stretch, in metres along the route polyline the backend received, the time lost on
/// it (nil when TomTom does not say), and who says so: "tomtom", "crowd" for the drivers' own
/// jams, "datagouv" for the DIR's feeds ([kind]: speed, works, incident, queue, closed).
public struct TrafficStretch: Sendable, Hashable {
    /// A section the backend sends without a source is TomTom's.
    public static let tomtom = "tomtom"
    /// HERE's live traffic, since 30/09.
    public static let here = "here"
    public static let crowd = "crowd"
    public static let datagouv = "datagouv"

    public let fromMeters: Double
    public let toMeters: Double
    public let level: TrafficLevel
    public let delaySeconds: Int?
    public let source: String
    public let kind: String?

    public init(
        fromMeters: Double, toMeters: Double, level: TrafficLevel, delaySeconds: Int? = nil,
        source: String = TrafficStretch.tomtom, kind: String? = nil
    ) {
        self.fromMeters = fromMeters
        self.toMeters = toMeters
        self.level = level
        self.delaySeconds = delaySeconds
        self.source = source
        self.kind = kind
    }

    func moved(from: Double, to: Double, delay: Int?) -> TrafficStretch {
        TrafficStretch(fromMeters: from, toMeters: to, level: level, delaySeconds: delay, source: source, kind: kind)
    }
}

/// Trafic du trajet : tronçons ralentis, distances mesurées par le backend.
/// worthChecking déclenche le contrôle automatique d’un détour possible.
public struct RouteTraffic: Sendable, Hashable {
    public let totalMeters: Double
    public let stretches: [TrafficStretch]
    public let worthChecking: Bool
    /// TomTom's time with today's traffic for the route from [startMeters] on; nil without TomTom.
    public let travelSeconds: Int?
    /// Where TomTom's time starts, in the same metres: the driver's place when it was asked.
    public let startMeters: Double

    public init(totalMeters: Double, stretches: [TrafficStretch], worthChecking: Bool = false, travelSeconds: Int? = nil, startMeters: Double = 0) {
        self.totalMeters = totalMeters
        self.stretches = stretches
        self.worthChecking = worthChecking
        self.travelSeconds = travelSeconds
        self.startMeters = startMeters
    }

    /// Whether a slowed stretch covers [meters] along the route ([routeMeters], the app's own
    /// length of it: the backend's measure is scaled to it).
    public func slowed(at meters: Double, routeMeters: Double) -> Bool {
        let scale = totalMeters > 0 ? routeMeters / totalMeters : 1
        return stretches.contains { $0.fromMeters * scale <= meters && meters <= $0.toMeters * scale }
    }

    /// The sources of its stretches, each once, in order ("tomtom", "crowd"); none on a clear road.
    public var sources: [String] {
        var seen: [String] = []
        for stretch in stretches where !seen.contains(stretch.source) {
            seen.append(stretch.source)
        }
        return seen
    }
}

/// What the backend said of the rest of the route (/api/traffic/route with raw: true): each source
/// whole, in metres of the polyline sent ([totalMeters] long); [tomtom] whether TomTom answered,
/// [datagouvShown] which ETA to show (D2.6), [minGapSeconds] the least wait before the next TomTom
/// recalage (D3.1).
public struct TrafficAnswer: Sendable, Hashable {
    public let totalMeters: Double
    public let stretches: [TrafficStretch]
    public let travelSeconds: Int?
    public let tomtom: Bool
    public let datagouvShown: Bool
    public let minGapSeconds: Int
    public let worthChecking: Bool

    public init(
        totalMeters: Double, stretches: [TrafficStretch], travelSeconds: Int?, tomtom: Bool,
        datagouvShown: Bool, minGapSeconds: Int, worthChecking: Bool
    ) {
        self.totalMeters = totalMeters
        self.stretches = stretches
        self.travelSeconds = travelSeconds
        self.tomtom = tomtom
        self.datagouvShown = datagouvShown
        self.minGapSeconds = minGapSeconds
        self.worthChecking = worthChecking
    }

    /// The stretches in metres of the whole route ([routeMeters] long), the answer being about its
    /// rest from [startMeters].
    public func placed(startMeters: Double, routeMeters: Double) -> [TrafficStretch] {
        let scale = totalMeters > 0 ? max(routeMeters - startMeters, 0) / totalMeters : 1
        return stretches.map {
            $0.moved(from: startMeters + $0.fromMeters * scale, to: startMeters + $0.toMeters * scale, delay: $0.delaySeconds)
        }
    }
}

/// The traffic of the route being followed, by source (D2.6, D2.7), in metres of the app's own
/// route ([routeMeters] long): TomTom's last answer ([tomtom], [travelSeconds] from [tomtomFrom]),
/// the drivers' jams and data.gouv's, each whole. [merged] joins them the way the backend does:
/// the drivers' jams where they cost more than TomTom, then data.gouv for its extra only (a
/// closure always), and only when asked: with and without it, the two ETAs. Same rules as Android.
public struct TrafficParts: Sendable, Hashable {
    public let routeMeters: Double
    public var tomtom: [TrafficStretch] = []
    public var travelSeconds: Int?
    public var tomtomFrom: Double = 0
    public var crowd: [TrafficStretch] = []
    public var datagouv: [TrafficStretch] = []
    public var datagouvShown = false
    public var worthChecking = false

    public init(routeMeters: Double) {
        self.routeMeters = routeMeters
    }

    /// Route du choix d'itinéraire : son temps HERE avec trafic, déjà connu, base de l'ETA dès le
    /// départ, avant la première réponse trafic. Aucun appel en plus. Nil sans temps HERE.
    public static func seeded(by route: Route, routeMeters: Double) -> TrafficParts? {
        guard let seconds = route.trafficSeconds, seconds > 0, routeMeters > 0 else { return nil }
        var parts = TrafficParts(routeMeters: routeMeters)
        parts.travelSeconds = seconds
        return parts
    }

    public func merged(withDatagouv: Bool? = nil) -> RouteTraffic {
        let known = tomtom + Self.extra(over: tomtom, zones: crowd, keepFree: false)
        let all = (withDatagouv ?? datagouvShown) ? known + Self.extra(over: known, zones: datagouv, keepFree: true) : known
        return RouteTraffic(
            totalMeters: routeMeters, stretches: all.sorted { $0.fromMeters < $1.fromMeters },
            worthChecking: worthChecking, travelSeconds: travelSeconds, startMeters: tomtomFrom
        )
    }

    /// The sources that said something on this route (the live one by its own name: here, tomtom).
    public var sources: [String] {
        var seen: [String] = []
        for stretch in tomtom where !seen.contains(stretch.source) { seen.append(stretch.source) }
        if travelSeconds != nil && tomtom.isEmpty { seen.append(TrafficStretch.here) }
        if !crowd.isEmpty { seen.append(TrafficStretch.crowd) }
        if !datagouv.isEmpty { seen.append(TrafficStretch.datagouv) }
        return seen
    }

    /// [zones] beyond what [over] already counts where they overlap: only their extra delay; with
    /// [keepFree], a closure or a stretch without delay shows anyway.
    public static func extra(over known: [TrafficStretch], zones: [TrafficStretch], keepFree: Bool) -> [TrafficStretch] {
        zones.compactMap { zone in
            let counted = known.reduce(0.0) { sum, s in
                let overlap = min(s.toMeters, zone.toMeters) - max(s.fromMeters, zone.fromMeters)
                guard overlap > 0, s.toMeters > s.fromMeters else { return sum }
                return sum + Double(s.delaySeconds ?? 0) * overlap / (s.toMeters - s.fromMeters)
            }
            let extra = Int((Double(zone.delaySeconds ?? 0) - counted).rounded())
            if extra > 0 { return zone.moved(from: zone.fromMeters, to: zone.toMeters, delay: extra) }
            if keepFree && (zone.level == .closed || (zone.delaySeconds ?? 0) == 0) {
                return zone.moved(from: zone.fromMeters, to: zone.toMeters, delay: 0)
            }
            return nil
        }
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
