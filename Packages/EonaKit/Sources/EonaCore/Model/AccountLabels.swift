import Foundation

/// What the menu and the profile say about an account, as on Android.
public enum AccountLabels {
    /// "Essai gratuit · 3 j restants", "Membre · jusqu'au 12/03/2027", "Accès restreint".
    public static func access(_ account: Account?, nowMillis: Int, timeZone: TimeZone = .current) -> String {
        guard let account else { return "Invité" }
        if account.role == .admin { return "Admin" }
        if account.access == .restricted || !account.canNavigate { return "Accès restreint" }
        if account.access == .trial { return "Essai gratuit · \(daysLeft(account.accessEndsAt, nowMillis: nowMillis))" }
        if account.accessEndsAt != nil { return "Membre · jusqu'au \(shortDate(account.accessEndsAt, timeZone: timeZone))" }
        return "Membre"
    }

    /// "Changer de pseudo" not possible yet: "Prochain changement le 25/09/2026"; nil when it is.
    public static func usernameChange(_ account: Account?, nowMillis: Int, timeZone: TimeZone = .current) -> String? {
        guard let end = isoEpochMillis(account?.usernameChangeableAt), end > nowMillis else { return nil }
        return "Prochain changement le \(shortDate(account?.usernameChangeableAt, timeZone: timeZone))"
    }

    /// "12/03/2027"; "—" when the date is missing or unreadable.
    public static func shortDate(_ iso: String?, timeZone: TimeZone = .current) -> String {
        guard let millis = isoEpochMillis(iso) else { return "—" }
        let day = gregorianCalendar(in: timeZone).dateComponents([.day, .month, .year], from: Date(millis: millis))
        return "\(twoDigits(day.day ?? 0))/\(twoDigits(day.month ?? 0))/\(day.year ?? 0)"
    }

    /// The trust score (0...5) to half a star, halves to even like Kotlin's `round`.
    public static func trustRounded(_ score: Double) -> Double {
        (score * 2).rounded(.toNearestOrEven) / 2
    }

    /// "3,5".
    public static func trustLabel(_ score: Double) -> String {
        frenchOneDecimal(trustRounded(score))
    }

    static func daysLeft(_ iso: String?, nowMillis: Int) -> String {
        guard let end = isoEpochMillis(iso) else { return "7 j" }
        let days = max((end - nowMillis) / 86_400_000, 0)
        return days <= 1 ? "dernier jour" : "\(days) j restants"
    }
}

/// The figures of the statistics page.
public enum StatsLabels {
    /// Minutes, then hours, never days: "45 min", "2h05", "2460h".
    public static func hours(seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        if minutes < 600 { return "\(minutes / 60)h\(twoDigits(minutes % 60))" }
        return "\(minutes / 60)h"
    }

    /// "9,5 km", "3 240 km".
    public static func kilometers(meters: Int) -> String {
        let km = Double(meters) / 1000.0
        return km < 10 ? "\(frenchOneDecimal(km)) km" : "\(grouped(Int(km))) km"
    }

    /// 3240 → "3 240".
    public static func grouped(_ value: Int) -> String {
        let digits = Array(String(value).reversed())
        let groups = stride(from: 0, to: digits.count, by: 3).map { String(digits[$0..<min($0 + 3, digits.count)]) }
        return String(groups.joined(separator: " ").reversed())
    }
}
