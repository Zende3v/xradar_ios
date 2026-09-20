import Foundation

/// A guest's daily limits and what they used, as the backend counts them: per day, Paris time.
public struct DailyLimits: Sendable, Hashable {
    /// The Paris day the counts are for, "yyyy-MM-dd".
    public let day: String
    public let reportsPerDay: Int
    public let reportsToday: Int
    public let tripsPerDay: Int
    public let tripsToday: Int

    public init(day: String, reportsPerDay: Int, reportsToday: Int, tripsPerDay: Int, tripsToday: Int) {
        self.day = day
        self.reportsPerDay = reportsPerDay
        self.reportsToday = reportsToday
        self.tripsPerDay = tripsPerDay
        self.tripsToday = tripsToday
    }

    /// Reports posted on [now]'s day: none when the counts are from another day.
    public func reportsUsed(now: Date = Date()) -> Int {
        day == Self.parisDay(now) ? reportsToday : 0
    }

    public func tripsUsed(now: Date = Date()) -> Int {
        day == Self.parisDay(now) ? tripsToday : 0
    }

    public func reportsLeft(now: Date = Date()) -> Int {
        max(reportsPerDay - reportsUsed(now: now), 0)
    }

    public func tripsLeft(now: Date = Date()) -> Int {
        max(tripsPerDay - tripsUsed(now: now), 0)
    }

    /// The day of [date] in France, "yyyy-MM-dd", as the backend dates its counts.
    public static func parisDay(_ date: Date) -> String {
        let paris = gregorianCalendar(in: TimeZone(identifier: "Europe/Paris") ?? .gmt)
        let parts = paris.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(twoDigits(parts.month ?? 0))-\(twoDigits(parts.day ?? 0))"
    }
}

/// A membership plan. Prices only: there is no payment in the app yet.
public struct SubscriptionPlan: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let priceCents: Int
    public let months: Int

    public static let monthly = SubscriptionPlan(id: "monthly", title: "Mensuel", priceCents: 1299, months: 1)
    public static let yearly = SubscriptionPlan(id: "yearly", title: "Annuel", priceCents: 14388, months: 12)
    public static let all = [monthly, yearly]

    /// "12,99 €"
    public var priceLabel: String {
        Self.euros(priceCents)
    }

    /// "/mois", "/an"
    public var periodLabel: String {
        switch months {
        case 1: "/mois"
        case 12: "/an"
        default: "/\(months) mois"
        }
    }

    /// A longer plan's cost per month, "soit 11,99 €/mois"; nil for the monthly plan.
    public var perMonthLabel: String? {
        guard months > 1 else { return nil }
        let cents = Int((Double(priceCents) / Double(months)).rounded())
        return "soit \(Self.euros(cents))/mois"
    }

    /// What this plan saves against paying monthly for as long, "-7,7 %"; nil when nothing.
    public var savingLabel: String? {
        let monthly = SubscriptionPlan.monthly.priceCents * months
        guard months > 1, priceCents < monthly else { return nil }
        let percent = Double(monthly - priceCents) / Double(monthly) * 100
        return "-\(frenchDecimal(percent, places: 1))\u{00A0}%"
    }

    static func euros(_ cents: Int) -> String {
        "\(cents / 100),\(twoDigits(cents % 100))\u{00A0}€"
    }
}
