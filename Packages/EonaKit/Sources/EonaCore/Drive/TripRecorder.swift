import Foundation

/// The traffic where the car stands still, as the drive screen knows it (D1.4): a long stop in a
/// jam is part of the drive, one on a clear road is a pause no ETA can foresee.
public enum StopTraffic: Sendable, Hashable {
    /// On a slowed stretch of the route, or a drivers' jam reported close by.
    case jam
    /// On the route, its traffic known, and clear here.
    case clear
    /// No traffic known yet, off the route, or no route.
    case unknown
}

/// A trip being driven, fed fix by fix: distance, top speed, standstills, the alerts met and the
/// route's estimate. Once the trip is over it makes the history record. Same rules as Android.
///
/// It also measures the ETA and the routes (D1.7): the real departure, the ETA shown at 0, 25, 50
/// and 75 % of the way, the long stops split into pauses and uncertain ones, and the routes and
/// traffic used. [platform] and [appVersion] say who recorded it.
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
    /// From this long, a stop outside a jam is a pause (D1.4).
    static let longStopSeconds = 300.0
    /// An alert counts as met once it is this close.
    static let metMeters = 300
    /// The ETA is kept at these percentages of the way.
    static let checkpoints = [25, 50, 75]
    /// The dock's ETA: the route's time pro rata of what is left of it (TripProgress).
    public static let etaMode = EtaEstimator.mode
    /// The engine of a route that does not say.
    static let unknownEngine = "unknown"
    /// Premier mouvement : deux points de suite à cette vitesse ou plus (km/h).
    static let movingKmh = 10.0
    /// Arrêt du conducteur à moins de cette distance de la destination : arrivé (m).
    public static let nearMeters = 300.0
    /// Un relevé par minute après départ, 4 h au plus ; 300 arrêts au plus. Comme le backend.
    static let sampleEveryMs = 60_000
    static let timelineMax = 240
    static let stopLogMax = 300
    /// Tracé GPS : un point toutes les 5 s, 20 000 au plus (plus de 27 h). Comme Android.
    static let traceEveryMs = 5_000
    static let traceMax = 20_000

    /// Identifiant du trajet : même valeur pour l'instantané d'app fermée et l'envoi final.
    public let id: String
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

    private let platform: String
    private let appVersion: String
    /// When the driver first joined the route (epoch millis); nil before.
    public private(set) var departedAt: Int?
    /// The distance of the route in force at the departure.
    public private(set) var plannedMeters: Int?
    /// The last route the trip followed.
    public private(set) var route: Route?
    private var departedMeters = 0.0
    private var manualStart = false
    /// The destination changed on the way (P1.6): the ETA report leaves the trip out.
    private var retargeted = false
    private var mapVersion: String?
    private var pausedSeconds = 0.0
    private var uncertainSeconds = 0.0
    // The stop running: one of its fixes was in a jam; all of them were on a clear road.
    private var stopInJam = false
    private var stopAllClear = true
    private var etaChecks: [EtaCheck] = []
    private var recalcCount = 0
    private var fasterCount = 0
    private var engines: [String] = []
    private var trafficSources: [String] = []
    /// Destination, pour la distance de fin seulement : jamais envoyée.
    private var destination: GeoPoint?
    /// Dernier point reçu (epoch millis) et sa vitesse.
    public private(set) var lastFixAt: Int?
    private var lastKmh = 0.0
    private var firstMoveAt: Int?
    /// Premier point d'une suite à 10 km/h ou plus, pas encore confirmée.
    private var movingSince: Int?
    /// Mètres roulés au début de l'arrêt en cours.
    private var stoppedAtMeters = 0.0
    private var stopLog: [TripStop] = []
    private var timeline: [TripSample] = []
    /// Tracé GPS du trajet, envoyé à part des mesures.
    public private(set) var trace: [TracePoint] = []

    /// Departed, and an ETA checkpoint still to come: [checkpoint] wants the next fixes.
    public var awaitsCheckpoint: Bool {
        departedAt != nil && etaChecks.filter { $0.at > 0 }.count < Self.checkpoints.count
    }

    public init(
        toLabel: String, to destination: GeoPoint? = nil, platform: String = "ios", appVersion: String = "",
        startedAt: Date = Date(), id: String = UUID().uuidString.lowercased()
    ) {
        self.id = id
        self.toLabel = toLabel
        self.destination = destination
        self.platform = platform
        self.appVersion = appVersion
        self.startedAt = startedAt
    }

    /// The destination changed on the way: the next route gives the new estimate.
    public mutating func retarget(_ label: String, to destination: GeoPoint? = nil) {
        toLabel = label
        if let destination { self.destination = destination }
        plannedSeconds = nil
        retargeted = true
    }

    /// The trip's route: the time already driven plus its estimate, once per destination.
    public mutating func plan(_ route: Route, now: Date = Date()) {
        guard plannedSeconds == nil else { return }
        plannedSeconds = Int(now.timeIntervalSince(startedAt).rounded()) + route.expectedSeconds
    }

    /// A route the trip follows (the first one, a recalculation, a faster one): its engine counts.
    public mutating func follow(_ route: Route) {
        self.route = route
        let engine = route.engine ?? Self.unknownEngine
        if !engines.contains(engine) { engines.append(engine) }
    }

    /// Leaving the route gave a new one.
    public mutating func recalculated() {
        recalcCount += 1
    }

    /// The trip switched to a faster route.
    public mutating func tookFaster() {
        fasterCount += 1
    }

    /// The route's traffic came from these sources ("tomtom", "crowd").
    public mutating func sawTraffic(_ sources: [String]) {
        for source in sources where !trafficSources.contains(source) {
            trafficSources.append(source)
        }
    }

    /// The real departure, once per trip: the driver joins the route ([manualStart]: the first fix of
    /// a trip started by hand). [route], then in force, gives the planned distance and the map, and
    /// the arrival the dock shows ([arrival]; else [route]'s time pro rata of [remainingShare]) is
    /// the 0 % checkpoint.
    /// [base] et [engineLeftSeconds] : base de l'ETA et temps restant moteur seul, gardés avec le
    /// relevé 0 % (nil : inconnus).
    public mutating func depart(
        route: Route?, remainingShare: Double, arrival: Date? = nil, both: EtaPair? = nil, manualStart: Bool,
        base: String? = nil, engineLeftSeconds: Double? = nil, now: Date = Date()
    ) {
        guard departedAt == nil else { return }
        departedAt = Self.millis(now)
        departedMeters = distanceMeters
        self.manualStart = manualStart
        plannedMeters = route?.distanceMeters
        mapVersion = route?.mapVersion
        // The 0 % checkpoint is the ETA shown at the departure itself: none without a route then
        // (a later route never makes one up, as on Android).
        if let route {
            keepEta(
                at: 0, route: route, remainingShare: remainingShare, arrival: arrival, both: both,
                base: base, engineLeftSeconds: engineLeftSeconds, now: now
            )
        }
    }

    /// After the departure, at each fix: the arrival the dock shows now ([arrival]; else [route]'s
    /// time pro rata of [remainingShare]) is kept the first time the trip is 25, 50 and 75 % done.
    /// Done: the metres driven since the departure, over those plus the metres of [route] left.
    public mutating func checkpoint(
        route: Route, remainingShare: Double, arrival: Date? = nil, both: EtaPair? = nil,
        base: String? = nil, engineLeftSeconds: Double? = nil, now: Date = Date()
    ) {
        guard awaitsCheckpoint else { return }
        let share = min(max(remainingShare, 0), 1)
        let driven = distanceMeters - departedMeters
        let total = driven + Double(route.distanceMeters) * share
        guard total > 0 else { return }
        let done = driven / total
        for at in Self.checkpoints where done >= Double(at) / 100 && !etaChecks.contains(where: { $0.at == at }) {
            keepEta(
                at: at, route: route, remainingShare: share, arrival: arrival, both: both,
                base: base, engineLeftSeconds: engineLeftSeconds, now: now
            )
        }
    }

    /// The ETA the dock shows at [now], kept as checkpoint [at].
    private mutating func keepEta(
        at: Int, route: Route, remainingShare: Double, arrival: Date?, both: EtaPair?,
        base: String?, engineLeftSeconds: Double?, now: Date
    ) {
        let share = min(max(remainingShare, 0), 1)
        let shownAt = Self.millis(now)
        etaChecks.append(EtaCheck(
            at: at,
            shownAt: shownAt,
            arrivalAt: arrival.map { Self.millis($0) } ?? shownAt + Int((Double(route.expectedSeconds) * share).rounded()) * 1000,
            pausedBefore: Int(pausedSeconds.rounded()),
            uncertainBefore: Int(uncertainSeconds.rounded()),
            withDatagouvAt: both.map { Self.millis($0.withDatagouv) },
            withoutDatagouvAt: both.map { Self.millis($0.withoutDatagouv) },
            base: base,
            engineLeftS: engineLeftSeconds.map { Int($0.rounded()) }
        ))
    }

    /// Après départ, à chaque point : un relevé par minute au plus. [leftMeters] et [leftSeconds] :
    /// restant de la route et ETA calculée ; [engineLeftSeconds] : restant moteur seul.
    public mutating func sample(
        leftMeters: Double, leftSeconds: Double, engineLeftSeconds: Double?, base: String, now: Date = Date()
    ) {
        guard departedAt != nil, timeline.count < Self.timelineMax else { return }
        let at = Self.millis(now)
        if let last = timeline.last, at - last.t < Self.sampleEveryMs { return }
        timeline.append(TripSample(
            t: at,
            drivenM: Int(distanceMeters.rounded()),
            leftM: Int(max(leftMeters, 0).rounded()),
            leftS: Int(max(leftSeconds, 0).rounded()),
            engineLeftS: engineLeftSeconds.map { Int(max($0, 0).rounded()) },
            base: base,
            kmh: Int(lastKmh.rounded())
        ))
    }

    /// [trafficHere] is asked only while the car stands still.
    public mutating func add(_ fix: LocationSample, trafficHere: () -> StopTraffic = { .unknown }) {
        if let lastLat, let lastLon {
            let step = Geo.haversine(lat1: lastLat, lon1: lastLon, lat2: fix.latitude, lon2: fix.longitude)
            if Self.stepMeters.contains(step) { distanceMeters += step }
        }
        lastLat = fix.latitude
        lastLon = fix.longitude
        let kmh = fix.speedKmh
        topSpeedKmh = max(topSpeedKmh, Int(kmh.rounded()))
        lastFixAt = fix.timeMs
        lastKmh = kmh
        if trace.count < Self.traceMax, trace.last.map({ fix.timeMs - $0.t >= Self.traceEveryMs }) ?? true {
            trace.append(TracePoint(
                t: fix.timeMs,
                lat: (fix.latitude * 1e6).rounded() / 1e6,
                lon: (fix.longitude * 1e6).rounded() / 1e6,
                kmh: fix.speedMps.map { ($0 * 36).rounded() / 10 },
                accuracyM: fix.accuracyM.map { ($0 * 10).rounded() / 10 },
                course: fix.bearingDeg.map { ($0 * 10).rounded() / 10 }
            ))
        }
        // Premier mouvement réel : deux points de suite à 10 km/h, une pointe GPS seule ne compte pas.
        if firstMoveAt == nil {
            if kmh >= Self.movingKmh {
                if let since = movingSince { firstMoveAt = since } else { movingSince = fix.timeMs }
            } else {
                movingSince = nil
            }
        }

        let at = Date(millis: fix.timeMs)
        if kmh < Self.stoppedKmh {
            if stoppedSince == nil {
                stoppedSince = at
                stoppedAtMeters = distanceMeters
                stopInJam = false
                stopAllClear = true
            }
            switch trafficHere() {
            case .jam:
                stopInJam = true
                stopAllClear = false
            case .clear:
                break
            case .unknown:
                stopAllClear = false
            }
        } else if let since = stoppedSince {
            stoppedSince = nil
            let still = at.timeIntervalSince(since)
            if still >= Self.minStopSeconds {
                stops += 1
                stoppedSeconds += still
                if stopLog.count < Self.stopLogMax {
                    stopLog.append(TripStop(
                        at: Self.millis(since), seconds: Int(still.rounded()),
                        drivenM: Int(stoppedAtMeters.rounded()), jam: stopInJam
                    ))
                }
            }
            // A long stop in a jam is part of the drive; on a road known clear all along it is a
            // pause, otherwise it stays uncertain.
            if still >= Self.longStopSeconds && !stopInJam {
                if stopAllClear {
                    pausedSeconds += still
                } else {
                    uncertainSeconds += still
                }
            }
        }
    }

    /// The alerts on the HUD now: each one reached counts once.
    public mutating func meet(_ alerts: [RoadAlert]) {
        for alert in alerts where alert.distanceMeters <= Self.metMeters && met[alert.key] == nil {
            met[alert.key] = alert.type
        }
    }

    /// Trajet assez long pour l'historique et les statistiques : 500 m et 60 s. Comme le backend.
    public static func isLongEnough(_ trip: TripRecord) -> Bool {
        Double(trip.distanceMeters) >= minMeters && Double(trip.durationSeconds) >= minSeconds
    }

    /// Distance du dernier point à la destination, mètres ; nil inconnue.
    public var endDistanceMeters: Double? {
        guard let destination, let lastLat, let lastLon else { return nil }
        return Geo.haversine(lat1: lastLat, lon1: lastLon, lat2: destination.lat, lon2: destination.lon)
    }

    /// The history record, or nil for a trip too short to keep. [arrived]: it ended at the
    /// destination. A standstill still running at the end (parked at the destination) is not a stop.
    /// Arrêt ou app fermée ([interrupted]) à moins de [nearMeters] de la destination : arrivé.
    /// [keepShort] : trajet gardé même sous 500 m ou 60 s (collecte serveur, tout est envoyé).
    public func record(
        id: String, arrived: Bool = false, interrupted: Bool = false, keepShort: Bool = false, now: Date = Date()
    ) -> TripRecord? {
        let duration = now.timeIntervalSince(startedAt)
        guard keepShort || (distanceMeters >= Self.minMeters && duration >= Self.minSeconds) else { return nil }
        let endDistance = endDistanceMeters
        let near = endDistance.map { $0 <= Self.nearMeters } ?? false
        let end = arrived ? TripEnd.arrived : interrupted ? TripEnd.interrupted : near ? TripEnd.near : TripEnd.stopped
        var events: [AlertType: Int] = [:]
        for type in met.values {
            events[type, default: 0] += 1
        }
        return TripRecord(
            id: id,
            startedAt: Self.millis(startedAt),
            fromLabel: "Ma position",
            toLabel: toLabel,
            distanceMeters: Int(distanceMeters.rounded()),
            durationSeconds: Int(duration),
            alertsCount: met.count,
            topSpeedKmh: topSpeedKmh,
            plannedSeconds: plannedSeconds,
            stops: stops,
            stoppedSeconds: Int(stoppedSeconds.rounded()),
            events: events,
            measure: TripMeasure(
                arrived: arrived || near,
                departedAt: departedAt,
                manualStart: manualStart,
                plannedMeters: plannedMeters,
                pausedSeconds: Int(pausedSeconds.rounded()),
                uncertainSeconds: Int(uncertainSeconds.rounded()),
                etaChecks: etaChecks,
                recalcCount: recalcCount,
                fasterCount: fasterCount,
                engines: engines,
                mapVersion: mapVersion,
                appVersion: appVersion,
                platform: platform,
                etaMode: Self.etaMode,
                trafficSources: trafficSources,
                retargeted: retargeted,
                firstMoveAt: firstMoveAt,
                lastFixAt: lastFixAt,
                endReason: end,
                endDistanceM: endDistance.map { Int($0.rounded()) },
                timeline: timeline,
                stopLog: stopLog
            )
        )
    }

    /// Epoch millis, as the history stores times.
    private static func millis(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 * 1000)
    }
}

/// The two arrivals of D2.6, with and without data.gouv's traffic, for the trip's measures.
public struct EtaPair: Sendable, Hashable {
    public let withDatagouv: Date
    public let withoutDatagouv: Date

    public init(withDatagouv: Date, withoutDatagouv: Date) {
        self.withDatagouv = withDatagouv
        self.withoutDatagouv = withoutDatagouv
    }
}
