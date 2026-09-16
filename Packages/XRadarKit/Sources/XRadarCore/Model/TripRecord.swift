import Foundation

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
        events: [AlertType: Int] = [:]
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
