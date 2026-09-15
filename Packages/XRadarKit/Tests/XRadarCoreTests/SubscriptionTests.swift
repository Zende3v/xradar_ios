import Foundation
import Testing
@testable import XRadarCore

struct SubscriptionTests {
    @Test func plansAndTheirSaving() {
        #expect(SubscriptionPlan.monthly.priceLabel == "12,99\u{00A0}€")
        #expect(SubscriptionPlan.monthly.periodLabel == "/mois")
        #expect(SubscriptionPlan.monthly.savingLabel == nil)
        #expect(SubscriptionPlan.monthly.perMonthLabel == nil)
        #expect(SubscriptionPlan.yearly.priceLabel == "143,88\u{00A0}€")
        #expect(SubscriptionPlan.yearly.periodLabel == "/an")
        #expect(SubscriptionPlan.yearly.savingLabel == "-7,7\u{00A0}%")
        #expect(SubscriptionPlan.yearly.perMonthLabel == "soit 11,99\u{00A0}€/mois")
    }

    @Test func dailyLimitsCountOnlyForTheirParisDay() throws {
        // 23:30 and 00:30 in Paris (UTC+2 in September).
        let lateEvening = try #require(ISO8601DateFormatter().date(from: "2026-09-15T21:30:00Z"))
        let afterMidnight = try #require(ISO8601DateFormatter().date(from: "2026-09-15T22:30:00Z"))
        #expect(DailyLimits.parisDay(lateEvening) == "2026-09-15")
        #expect(DailyLimits.parisDay(afterMidnight) == "2026-09-16")
        let limits = DailyLimits(day: "2026-09-15", reportsPerDay: 5, reportsToday: 5, tripsPerDay: 7, tripsToday: 3)
        #expect(limits.reportsLeft(now: lateEvening) == 0)
        #expect(limits.tripsLeft(now: lateEvening) == 4)
        #expect(limits.reportsLeft(now: afterMidnight) == 5)
        #expect(limits.tripsUsed(now: afterMidnight) == 0)
    }
}
