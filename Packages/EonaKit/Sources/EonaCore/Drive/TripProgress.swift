import Foundation

public extension TripInfo {
    /// Time left, distance left and arrival time, as the HUD dock shows them ("1 h 02", "12 km",
    /// "20:02"). [remainingShare] is the part of [route] still ahead of the driver (1 before they
    /// are on it, 0 at the destination): the route's own time and distance shrink with it, the same
    /// way the shared trip and the group count what is left.
    static func of(
        _ route: Route,
        remainingShare: Double = 1,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> TripInfo {
        let share = min(max(remainingShare, 0), 1)
        let seconds = Double(route.durationSeconds) * share
        // Still on the way, never "0 min": the last minute shows as one.
        let minutes = share > 0 ? max(roundToInt(seconds / 60.0), 1) : 0
        let remaining = minutes >= 60 ? "\(minutes / 60) h \(twoDigits(minutes % 60))" : "\(minutes) min"
        let arrival = gregorianCalendar(in: timeZone)
            .dateComponents([.hour, .minute], from: now.addingTimeInterval(seconds))
        return TripInfo(
            remainingLabel: remaining,
            distanceLabel: distanceLabel(meters: Double(route.distanceMeters) * share),
            arrivalLabel: "\(twoDigits(arrival.hour ?? 0)):\(twoDigits(arrival.minute ?? 0))"
        )
    }

    /// "450 m" under a kilometre (to 10 m), "4,3 km" under ten, "12 km" beyond.
    static func distanceLabel(meters: Double) -> String {
        let tens = roundToInt(meters / 10) * 10
        if tens < 1000 { return "\(tens) m" }
        let km = meters / 1000.0
        return km >= 10 ? "\(roundToInt(km)) km" : "\(frenchOneDecimal(km)) km"
    }
}
