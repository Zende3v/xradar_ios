import Foundation

/// One driver of a finished group trip, as the history keeps it: who they are, where they came
/// in, how long it took them. No route, no position — the ranking, and nothing else.
public struct TripGroupRank: Sendable, Hashable, Codable {
    public let name: String
    /// nil for a driver who never arrived.
    public let rank: Int?
    public let durationSeconds: Int?
    public let distanceMeters: Int?
    /// True for the line of whoever owns this history.
    public let me: Bool

    public init(name: String, rank: Int?, durationSeconds: Int?, distanceMeters: Int?, me: Bool) {
        self.name = name
        self.rank = rank
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.me = me
    }

    /// "1er", "3e", "—".
    public var rankLabel: String {
        guard let rank else { return "—" }
        return rank == 1 ? "1er" : "\(rank)e"
    }

    /// "1 h 12 · 465 km" — what this driver did, as far as the group knew it.
    public var timeLabel: String {
        var parts: [String] = []
        if let durationSeconds { parts.append(TripRecord.duration(durationSeconds)) }
        if let distanceMeters { parts.append("\(distanceMeters / 1000) km") }
        return parts.isEmpty ? "Non parti" : parts.joined(separator: " · ")
    }
}

/// A trip driven in a group, as the history keeps it: the destination shared with the others, my
/// own rank, and the whole ranking. The others' routes are not kept — they were never ours.
public struct TripGroupResult: Sendable, Hashable, Codable {
    public let code: String
    public let myRank: Int?
    public let ranking: [TripGroupRank]

    public init(code: String, myRank: Int?, ranking: [TripGroupRank]) {
        self.code = code
        self.myRank = myRank
        self.ranking = ranking
    }

    /// "2e sur 4".
    public var standingLabel: String {
        let arrived = ranking.filter { $0.rank != nil }.count
        guard let myRank else { return "Non classé" }
        return "\(myRank == 1 ? "1er" : "\(myRank)e") sur \(max(arrived, myRank))"
    }
}

/// The ETA the dock showed at one point of the trip: [at] 0, 25, 50 or 75 % of the way, the moment
/// ([shownAt]) and the arrival announced ([arrivalAt]), in epoch millis, and the seconds of pauses
/// and uncertain stops before it (a stop still running then is not counted).
public struct EtaCheck: Sendable, Hashable, Codable {
    public let at: Int
    public let shownAt: Int
    public let arrivalAt: Int
    public let pausedBefore: Int
    public let uncertainBefore: Int

    public init(at: Int, shownAt: Int, arrivalAt: Int, pausedBefore: Int, uncertainBefore: Int) {
        self.at = at
        self.shownAt = shownAt
        self.arrivalAt = arrivalAt
        self.pausedBefore = pausedBefore
        self.uncertainBefore = uncertainBefore
    }
}

/// What a trip tells about the ETA and the routes (D1.7 of the Valhalla plan), sent with it; no
/// coordinates. Nil for a trip recorded before these measures. Same fields as Android and the
/// backend.
public struct TripMeasure: Sendable, Hashable, Codable {
    /// Ended by reaching the destination, not stopped on the way.
    public let arrived: Bool
    /// When the driver first joined the route (epoch millis); nil when they never did.
    public let departedAt: Int?
    /// The departure was chosen by hand, not the driver's position.
    public let manualStart: Bool
    /// The distance of the route in force at [departedAt].
    public let plannedMeters: Int?
    /// Long stops on a clear road (pauses), and those where the traffic was not known.
    public let pausedSeconds: Int
    public let uncertainSeconds: Int
    public let etaChecks: [EtaCheck]
    /// New routes after leaving the route, and switches to a faster one.
    public let recalcCount: Int
    public let fasterCount: Int
    /// The engines of the routes used, in the order met ("unknown" for a route that does not say).
    public let engines: [String]
    /// The map of the route in force at [departedAt].
    public let mapVersion: String?
    /// "1.0.0 (1)", "ios", and how the ETA was computed ("proportional").
    public let appVersion: String
    public let platform: String
    public let etaMode: String
    /// Where the route's traffic came from during the trip: "tomtom", "crowd".
    public let trafficSources: [String]
    /// The destination changed on the way; nil in measures saved before it was kept (= false).
    public let retargeted: Bool?

    public init(
        arrived: Bool,
        departedAt: Int?,
        manualStart: Bool,
        plannedMeters: Int?,
        pausedSeconds: Int,
        uncertainSeconds: Int,
        etaChecks: [EtaCheck],
        recalcCount: Int,
        fasterCount: Int,
        engines: [String],
        mapVersion: String?,
        appVersion: String,
        platform: String,
        etaMode: String,
        trafficSources: [String],
        retargeted: Bool = false
    ) {
        self.arrived = arrived
        self.departedAt = departedAt
        self.manualStart = manualStart
        self.plannedMeters = plannedMeters
        self.pausedSeconds = pausedSeconds
        self.uncertainSeconds = uncertainSeconds
        self.etaChecks = etaChecks
        self.recalcCount = recalcCount
        self.fasterCount = fasterCount
        self.engines = engines
        self.mapVersion = mapVersion
        self.appVersion = appVersion
        self.platform = platform
        self.etaMode = etaMode
        self.trafficSources = trafficSources
        self.retargeted = retargeted
    }
}

/// A completed trip in the history. Stores raw values; labels are derived for display.
public struct TripRecord: Sendable, Hashable {
    public let id: String
    /// Epoch millis.
    public let startedAt: Int
    public let fromLabel: String
    public let toLabel: String
    public let distanceMeters: Int
    public let durationSeconds: Int
    public let alertsCount: Int
    public let topSpeedKmh: Int
    /// The route's estimate for the trip, in seconds; nil when no route was known (or for a trip
    /// recorded before estimates were kept).
    public let plannedSeconds: Int?
    /// Standstills of 10 s or more on the way, and their total time.
    public let stops: Int
    public let stoppedSeconds: Int
    /// The alerts met on the way, per kind.
    public let events: [AlertType: Int]
    /// Set when the trip was driven in a group: the shared destination, my rank, the ranking.
    public let group: TripGroupResult?
    /// The ETA and route measures; nil for a trip recorded before them.
    public let measure: TripMeasure?

    public init(
        id: String,
        startedAt: Int,
        fromLabel: String,
        toLabel: String,
        distanceMeters: Int,
        durationSeconds: Int,
        alertsCount: Int,
        topSpeedKmh: Int,
        plannedSeconds: Int? = nil,
        stops: Int = 0,
        stoppedSeconds: Int = 0,
        events: [AlertType: Int] = [:],
        group: TripGroupResult? = nil,
        measure: TripMeasure? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.fromLabel = fromLabel
        self.toLabel = toLabel
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.alertsCount = alertsCount
        self.topSpeedKmh = topSpeedKmh
        self.plannedSeconds = plannedSeconds
        self.stops = stops
        self.stoppedSeconds = stoppedSeconds
        self.events = events
        self.group = group
        self.measure = measure
    }

    /// The same trip, with its group result — taken once the whole group has arrived.
    public func with(group: TripGroupResult?) -> TripRecord {
        TripRecord(
            id: id,
            startedAt: startedAt,
            fromLabel: fromLabel,
            toLabel: toLabel,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            alertsCount: alertsCount,
            topSpeedKmh: topSpeedKmh,
            plannedSeconds: plannedSeconds,
            stops: stops,
            stoppedSeconds: stoppedSeconds,
            events: events,
            group: group,
            measure: measure
        )
    }

    /// "12 km", "3,4 km".
    public var distanceLabel: String {
        let km = Double(distanceMeters) / 1000.0
        return km >= 10 ? "\(Int(km.rounded())) km" : "\(frenchOneDecimal(km)) km"
    }

    /// "45 min", "1 h 05".
    public var durationLabel: String {
        Self.duration(durationSeconds)
    }

    /// The route's estimate, "41 min"; nil without one.
    public var plannedLabel: String? {
        plannedSeconds.map { Self.duration($0) }
    }

    /// The real time against the estimate: "+4 min", "−3 min", or "À l'heure" within a minute;
    /// nil without an estimate.
    public var delayLabel: String? {
        guard let plannedSeconds else { return nil }
        let delta = durationSeconds - plannedSeconds
        guard abs(delta) >= 60 else { return "À l'heure" }
        return (delta > 0 ? "+" : "−") + Self.duration(abs(delta))
    }

    /// Over the whole trip, stops included, in km/h.
    public var averageSpeedKmh: Int {
        guard durationSeconds > 0 else { return 0 }
        return Int((Double(distanceMeters) / Double(durationSeconds) * 3.6).rounded())
    }

    /// "Aucun", "1 arrêt · 45 s", "3 arrêts · 2 min".
    public var stopsLabel: String {
        guard stops > 0 else { return "Aucun" }
        return "\(stops) arrêt\(stops > 1 ? "s" : "") · \(Self.duration(stoppedSeconds, withSeconds: true))"
    }

    /// "Aujourd'hui · 08:05", "Hier · 18:30", "10 sept. · 08:05" on the phone's clock.
    public var dateLabel: String {
        dateLabel(now: Date(), timeZone: .current)
    }

    public func dateLabel(now: Date, timeZone: TimeZone) -> String {
        let calendar = gregorianCalendar(in: timeZone)
        let date = Date(millis: startedAt)
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let time = "\(twoDigits(parts.hour ?? 0)):\(twoDigits(parts.minute ?? 0))"
        if calendar.isDate(date, inSameDayAs: now) {
            return "Aujourd'hui · \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Hier · \(time)"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM"
        return "\(formatter.string(from: date)) · \(time)"
    }

    /// "45 min", "1 h 05"; under a minute, "40 s" when [withSeconds].
    static func duration(_ total: Int, withSeconds: Bool = false) -> String {
        if withSeconds && total < 60 { return "\(total) s" }
        let minutes = total / 60
        return minutes >= 60 ? "\(minutes / 60) h \(twoDigits(minutes % 60))" : "\(minutes) min"
    }
}

public extension AlertType {
    /// The name a trip's events are stored under on the backend.
    var wireName: String {
        switch self {
        case .radarFixed: "radarFixed"
        case .radarMobile: "radarMobile"
        case .controlZone: "controlZone"
        case .camera: "camera"
        case .hazard: "hazard"
        case .accident: "accident"
        case .roadwork: "roadwork"
        case .radarCar: "radarCar"
        }
    }

    init?(wireName: String) {
        guard let type = Self.allCases.first(where: { $0.wireName == wireName }) else { return nil }
        self = type
    }
}
