import Foundation

/// One decimal with a French comma, halves rounded up, as the Android app prints "%.1f"
/// (1.25 → "1,3"). Rounds the shortest decimal form of the value, not its binary expansion.
func frenchOneDecimal(_ value: Double) -> String {
    var exact = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(value)
    var rounded = Decimal()
    NSDecimalRound(&rounded, &exact, 1, .plain)
    let tenths = NSDecimalNumber(decimal: rounded * 10).intValue
    return "\(tenths / 10),\(tenths % 10)"
}

/// "07", "12".
func twoDigits(_ value: Int) -> String {
    value < 10 ? "0\(value)" : "\(value)"
}

/// A Gregorian calendar on [timeZone].
func gregorianCalendar(in timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
}

extension Date {
    init(millis: Int) {
        self.init(timeIntervalSince1970: Double(millis) / 1000)
    }
}

extension Array {
    /// Sorted by an integer key, equal keys keeping their order (like Kotlin's `sortedBy`).
    func stableSorted(by key: (Element) -> Int) -> [Element] {
        enumerated()
            .sorted { lhs, rhs in
                let left = key(lhs.element)
                let right = key(rhs.element)
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
