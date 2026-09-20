import Foundation

/// The nearby list in two parts: the places to go to now, then those closed right now.
public struct NearbyResults: Sendable, Hashable {
    public let open: [Place]
    public let closed: [Place]

    public init(open: [Place], closed: [Place]) {
        self.open = open
        self.closed = closed
    }

    public var isEmpty: Bool {
        open.isEmpty && closed.isEmpty
    }
}

/// Which places the nearby search lists, and in what order, out of the pool the backend sends
/// (its 60 nearest).
///
/// Open places (and those whose hours are unknown) come first, nearest first; for fuel, the
/// [FuelStationPicker] still lets a station that shows a price go ahead in a city. Places closed
/// right now follow: only those nearer than the last open one listed, at most [closedLimit].
public enum NearbyPicker {

    public static let limit = FuelStationPicker.limit
    public static let closedLimit = 8

    public static func pick(_ pool: [Place], category: PlaceCategory, fuel: FuelType?, nowMillis: Int) -> NearbyResults {
        let nearest = pool.stableSorted { $0.distanceMeters ?? .max }
        var open: [Place] = []
        var closed: [Place] = []
        for place in nearest {
            if let hours = place.nearby?.hours, NearbyLabels.state(hours, nowMillis: nowMillis) == .closed {
                closed.append(place)
            } else {
                open.append(place)
            }
        }
        let shown = category == .fuel
            ? FuelStationPicker.pick(open, fuel: fuel, nowMillis: nowMillis)
            : Array(open.prefix(limit))
        let reach = shown.count >= limit ? (shown.map { $0.distanceMeters ?? 0 }.max() ?? 0) : Int.max
        let closedShown = closed.filter { ($0.distanceMeters ?? .max) <= reach }.prefix(closedLimit)
        return NearbyResults(open: shown, closed: Array(closedShown))
    }
}

/// The words the nearby list shows for a place: its opening state and its details.
public enum NearbyLabels {

    public enum Tone: Sendable, Hashable {
        case positive
        case warning
        case negative
        case neutral
    }

    /// "Ouvert" + "07:00–21:00", "Fermé" + "ouvre demain à 07:00"…
    public struct Status: Sendable, Hashable {
        public let text: String
        public let detail: String?
        public let tone: Tone
    }

    /// An open place closing within this is "Ferme bientôt".
    public static let closingSoonMillis = 30 * 60 * 1000

    /// The state at [nowMillis]. The backend read it when the list loaded; once its next change
    /// has passed the state flips, so a list left open does not keep saying "Ouvert".
    public static func state(_ hours: OpeningHours, nowMillis: Int) -> OpenState {
        guard let next = hours.nextChangeMillis, nowMillis >= next else { return hours.state }
        switch hours.state {
        case .open: return .closed
        case .closed: return .open
        case .unknown: return .unknown
        }
    }

    public static func status(_ hours: OpeningHours?, nowMillis: Int, timeZone: TimeZone = .current) -> Status? {
        guard let hours else { return nil }
        if hours.alwaysOpen { return Status(text: "Ouvert", detail: "24 h/24", tone: .positive) }
        let next = hours.nextChangeMillis.flatMap { $0 > nowMillis ? $0 : nil }
        switch state(hours, nowMillis: nowMillis) {
        case .open:
            if let next, next - nowMillis <= closingSoonMillis {
                return Status(text: "Ferme bientôt", detail: "à \(clock(next, timeZone: timeZone))", tone: .warning)
            }
            return Status(text: "Ouvert", detail: slots(hours.today), tone: .positive)
        case .closed:
            let detail = next.map { opensAt($0, nowMillis: nowMillis, timeZone: timeZone) }
            return Status(text: "Fermé", detail: detail, tone: .negative)
        case .unknown:
            return slots(hours.today).map { Status(text: "Horaires", detail: $0, tone: .neutral) }
        }
    }

    /// "07:00–12:00, 14:00–19:00"; "24 h/24" for the whole day; nil when there is none.
    public static func slots(_ today: [TimeSlot]) -> String? {
        if today.isEmpty { return nil }
        if today.contains(where: { $0.from == "00:00" && $0.to == "24:00" }) { return "24 h/24" }
        return today.map { "\($0.from)–\($0.to)" }.joined(separator: ", ")
    }

    /// "ouvre à 14:00", "ouvre demain à 07:00", "ouvre lun. à 07:00".
    public static func opensAt(_ atMillis: Int, nowMillis: Int, timeZone: TimeZone = .current) -> String {
        let calendar = gregorianCalendar(in: timeZone)
        let at = Date(millis: atMillis)
        let today = calendar.startOfDay(for: Date(millis: nowMillis))
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: at)).day ?? 0
        let time = clock(atMillis, timeZone: timeZone)
        switch days {
        case 0:
            return "ouvre à \(time)"
        case 1:
            return "ouvre demain à \(time)"
        default:
            let weekday = DateFormatter()
            weekday.locale = Locale(identifier: "fr_FR")
            weekday.timeZone = timeZone
            weekday.dateFormat = "EEE"
            return "ouvre \(weekday.string(from: at)) à \(time)"
        }
    }

    /// What matters for the place's kind, in reading order: the brand of a station (unless its
    /// name already says it), a charger's power and connectors, a car park's fee, type and
    /// size, a hotel's stars, and "Clients" when it is for customers only.
    public static func details(_ place: Place) -> [String] {
        guard let info = place.nearby else { return [] }
        var out: [String] = []
        if let brand = info.brand {
            let key = flat(brand)
            if !key.isEmpty, !flat(place.name).contains(key) { out.append(brand) }
        }
        if let charging = info.charging {
            if let kw = charging.maxKw { out.append(kilowatts(kw)) }
            out += charging.connectors
            if let points = charging.points { out.append(points == 1 ? "1 point" : "\(points) points") }
        }
        if let parking = info.parking {
            switch parking.fee {
            case true?: out.append("Payant")
            case false?: out.append("Gratuit")
            case nil: break
            }
            if parking.parkAndRide { out.append("Parking relais") }
            switch parking.type {
            case .underground?: out.append("Souterrain")
            case .multiStorey?: out.append("Silo")
            case .rooftop?: out.append("Sur le toit")
            case .streetSide?: out.append("Bord de rue")
            case .surface?, nil: break
            }
            if let capacity = parking.capacity { out.append(capacity == 1 ? "1 place" : "\(capacity) places") }
        }
        if let stars = info.stars { out.append(String(repeating: "★", count: stars)) }
        if info.customersOnly { out.append("Clients") }
        return out
    }

    /// "150 kW", "7,4 kW".
    public static func kilowatts(_ kw: Double) -> String {
        kw == kw.rounded() ? "\(Int(kw)) kW" : "\(frenchOneDecimal(kw)) kW"
    }

    /// "850 m" / "12,4 km": the driver reads a distance, not a number of metres.
    public static func distance(_ meters: Int) -> String {
        if meters < 1000 { return "\(meters) m" }
        let km = Double(meters) / 1000.0
        return meters < 10_000 ? "\(frenchOneDecimal(km)) km" : "\(Int(km.rounded())) km"
    }

    /// "21:00" on [timeZone]'s clock.
    private static func clock(_ atMillis: Int, timeZone: TimeZone) -> String {
        let parts = gregorianCalendar(in: timeZone).dateComponents([.hour, .minute], from: Date(millis: atMillis))
        return "\(twoDigits(parts.hour ?? 0)):\(twoDigits(parts.minute ?? 0))"
    }

    private static func flat(_ value: String) -> String {
        value.lowercased(with: Locale(identifier: "fr_FR")).filter { $0.isLetter || $0.isNumber }
    }
}
