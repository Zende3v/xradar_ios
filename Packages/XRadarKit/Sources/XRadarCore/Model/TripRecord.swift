import Foundation

/// A completed trip in the local history. Stores raw values; labels are derived for display.
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

    public init(
        id: String,
        startedAt: Int,
        fromLabel: String,
        toLabel: String,
        distanceMeters: Int,
        durationSeconds: Int,
        alertsCount: Int,
        topSpeedKmh: Int
    ) {
        self.id = id
        self.startedAt = startedAt
        self.fromLabel = fromLabel
        self.toLabel = toLabel
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.alertsCount = alertsCount
        self.topSpeedKmh = topSpeedKmh
    }

    /// "12 km", "3,4 km".
    public var distanceLabel: String {
        let km = Double(distanceMeters) / 1000.0
        return km >= 10 ? "\(Int(km.rounded())) km" : "\(frenchOneDecimal(km)) km"
    }

    /// "45 min", "1 h 05".
    public var durationLabel: String {
        let minutes = durationSeconds / 60
        return minutes >= 60 ? "\(minutes / 60) h \(twoDigits(minutes % 60))" : "\(minutes) min"
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
}
