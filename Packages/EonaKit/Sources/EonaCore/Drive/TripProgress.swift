import Foundation

public extension TripInfo {
    /// Time left, distance left and arrival time of [route], as the HUD dock shows them
    /// ("1 h 02", "12 km", "20:02").
    static func of(_ route: Route, now: Date = Date(), timeZone: TimeZone = .current) -> TripInfo {
        let minutes = roundToInt(Double(route.durationSeconds) / 60.0)
        let remaining = minutes >= 60 ? "\(minutes / 60) h \(twoDigits(minutes % 60))" : "\(minutes) min"
        let km = Double(route.distanceMeters) / 1000.0
        let distance = km >= 10 ? "\(roundToInt(km)) km" : "\(frenchOneDecimal(km)) km"
        let arrival = gregorianCalendar(in: timeZone)
            .dateComponents([.hour, .minute], from: now.addingTimeInterval(Double(route.durationSeconds)))
        return TripInfo(
            remainingLabel: remaining,
            distanceLabel: distance,
            arrivalLabel: "\(twoDigits(arrival.hour ?? 0)):\(twoDigits(arrival.minute ?? 0))"
        )
    }
}
