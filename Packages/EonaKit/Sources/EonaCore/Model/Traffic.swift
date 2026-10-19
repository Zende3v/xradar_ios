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

    /// Ce que [zones] ajoutent à [known], déjà compté (contrat fusion 20/10, même que backend).
    /// Densité = secondes / mètres. Sur chaque portion entre bornes : densité maximale des zones
    /// actives, moins somme des densités connues actives. Seul ce complément positif est rendu, sur
    /// sa portion réelle, avec les métadonnées de la zone dominante. Zones disjointes s'additionnent ;
    /// ordre et doublons sans effet. Arrondi cumulé : total rendu = total exact arrondi. Bornes non
    /// finies, vides, densité infinie ou retard absent/négatif : aucun temps. Marqueurs entiers à
    /// 0 s : fermeture toujours ; avec [keepFree], zone sans retard (nil ou zéro). Bornes finies,
    /// to ≥ from (point admis) ; intervalle inversé rejeté, jamais retourné. Tri puis balayage.
    public static func extra(over known: [TrafficStretch], zones: [TrafficStretch], keepFree: Bool) -> [TrafficStretch] {
        let counted = known.compactMap(Dense.init)
        let ranked = zones.compactMap(Dense.init).sorted(by: Dense.precedes)
        var exact = 0.0
        var given = 0
        var added: [TrafficStretch] = []
        for piece in complements(counted: counted, ranked: ranked) {
            exact += piece.seconds
            let total = Int(min(exact.rounded(), Double(Int.max / 2)))
            guard total > given else { continue }
            added.append(ranked[piece.rank].stretch.moved(from: piece.from, to: piece.to, delay: total - given))
            given = total
        }
        // Doublons retirés après passage à 0 s : même marqueur une fois, quel que soit le retard reçu.
        var markers = Set<TrafficStretch>()
        for zone in zones where zone.fromMeters.isFinite && zone.toMeters.isFinite && zone.toMeters >= zone.fromMeters {
            guard zone.level == .closed || (keepFree && (zone.delaySeconds ?? 0) == 0) else { continue }
            markers.insert(zone.moved(from: zone.fromMeters, to: zone.toMeters, delay: 0))
        }
        return (added + markers).sorted(by: Self.placedFirst)
    }

    /// Tronçon utilisable pour le calcul : bornes finies, largeur finie > 0, retard positif, densité finie.
    private struct Dense {
        let stretch: TrafficStretch
        let density: Double

        init?(_ stretch: TrafficStretch) {
            let length = stretch.toMeters - stretch.fromMeters
            guard stretch.fromMeters.isFinite, stretch.toMeters.isFinite, length.isFinite, length > 0,
                  let delay = stretch.delaySeconds, delay > 0 else { return nil }
            let density = Double(delay) / length
            guard density.isFinite, density > 0 else { return nil }
            self.stretch = stretch
            self.density = density
        }

        /// Priorité déterministe : densité décroissante, puis position et métadonnées.
        static func precedes(_ a: Dense, _ b: Dense) -> Bool {
            if a.density != b.density { return a.density > b.density }
            return TrafficParts.placedFirst(a.stretch, b.stretch)
        }
    }

    /// Ordre total des tronçons : bornes, retard, source, niveau, nature (absente d'abord).
    private static func placedFirst(_ a: TrafficStretch, _ b: TrafficStretch) -> Bool {
        if a.fromMeters != b.fromMeters { return a.fromMeters < b.fromMeters }
        if a.toMeters != b.toMeters { return a.toMeters < b.toMeters }
        if a.delaySeconds != b.delaySeconds { return (a.delaySeconds ?? Int.min) < (b.delaySeconds ?? Int.min) }
        if a.source != b.source { return a.source < b.source }
        if a.level != b.level { return a.level.rawValue < b.level.rawValue }
        if a.kind != b.kind { return (a.kind.map { "1" + $0 } ?? "0") < (b.kind.map { "1" + $0 } ?? "0") }
        return false
    }

    /// Complément exact d'une portion contiguë, dû à la zone de rang [rank].
    private struct Piece {
        var from: Double
        var to: Double
        var seconds: Double
        let density: Double
        let rank: Int
    }

    /// Balayage des bornes : zones actives dans un tas par rang, densité connue en somme courante.
    /// Portions contiguës d'une même zone et même complément fusionnées, sans étalement.
    private static func complements(counted: [Dense], ranked: [Dense]) -> [Piece] {
        guard !ranked.isEmpty else { return [] }
        var cuts: [Double] = []
        for cut in (counted + ranked).flatMap({ [$0.stretch.fromMeters, $0.stretch.toMeters] }).sorted() where cut != cuts.last {
            cuts.append(cut)
        }
        let byStart = ranked.indices.sorted { ranked[$0].stretch.fromMeters < ranked[$1].stretch.fromMeters }
        let starts = counted.sorted { ($0.stretch.fromMeters, $0.density) < ($1.stretch.fromMeters, $1.density) }
        let ends = counted.sorted { ($0.stretch.toMeters, $0.density) < ($1.stretch.toMeters, $1.density) }
        var heap = RankHeap()
        var next = 0, started = 0, ended = 0
        var knownDensity = 0.0
        var pieces: [Piece] = []
        for (from, to) in zip(cuts, cuts.dropFirst()) {
            while next < byStart.count, ranked[byStart[next]].stretch.fromMeters <= from {
                heap.push(byStart[next])
                next += 1
            }
            while started < starts.count, starts[started].stretch.fromMeters <= from {
                knownDensity += starts[started].density
                started += 1
            }
            while ended < ends.count, ends[ended].stretch.toMeters <= from {
                knownDensity -= ends[ended].density
                ended += 1
            }
            // Aucun connu actif : zéro exact, sans reste flottant.
            if started == ended { knownDensity = 0 }
            while let top = heap.top, ranked[top].stretch.toMeters <= from { heap.pop() }
            guard let top = heap.top else { continue }
            let density = ranked[top].density - max(knownDensity, 0)
            let seconds = density * (to - from)
            // Seuil sur le complément exact en secondes, pas sur la densité (même que backend).
            guard seconds > 1e-9 else { continue }
            if let last = pieces.last, last.rank == top, last.to == from,
               abs(last.density - density) <= 1e-12 * ranked[top].density {
                pieces[pieces.count - 1].to = to
                pieces[pieces.count - 1].seconds += seconds
            } else {
                pieces.append(Piece(from: from, to: to, seconds: seconds, density: density, rank: top))
            }
        }
        return pieces
    }

    /// Tas minimal de rangs : sommet = zone active la plus prioritaire.
    private struct RankHeap {
        private var items: [Int] = []

        var top: Int? { items.first }

        mutating func push(_ rank: Int) {
            items.append(rank)
            var child = items.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard items[child] < items[parent] else { return }
                items.swapAt(child, parent)
                child = parent
            }
        }

        mutating func pop() {
            guard !items.isEmpty else { return }
            items.swapAt(0, items.count - 1)
            items.removeLast()
            var parent = 0
            while true {
                let left = 2 * parent + 1
                var least = parent
                if left < items.count, items[left] < items[least] { least = left }
                if left + 1 < items.count, items[left + 1] < items[least] { least = left + 1 }
                if least == parent { return }
                items.swapAt(parent, least)
                parent = least
            }
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
