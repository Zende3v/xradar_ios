import Foundation
import Testing
import XRadarCore
@testable import XRadarData

private func object(_ text: String) throws -> JSON {
    JSON(try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]))
}

struct AccountLimitsTests {
    @Test func readsAndCachesTheDailyLimits() throws {
        let body = #"{"id":"u1","role":"guest","limits":{"day":"2026-09-15","reportsPerDay":5,"reportsToday":2,"tripsPerDay":7,"tripsToday":7}}"#
        let guest = AccountAPI.account(try object(body))
        #expect(guest.limits == DailyLimits(day: "2026-09-15", reportsPerDay: 5, reportsToday: 2, tripsPerDay: 7, tripsToday: 7))
        let cached = try JSONDecoder().decode(StoredAccount.self, from: JSONEncoder().encode(StoredAccount(guest)))
        #expect(cached.account.limits == guest.limits)
        #expect(AccountAPI.account(try object(#"{"id":"c1","role":"client","limits":null}"#)).limits == nil)
    }

    @Test func aCacheFromBeforeLimitsStillReads() throws {
        let old = #"{"id":"u1","role":"guest","banned":false,"emailVerified":false,"access":"trial","canNavigate":true,"trust":2.5}"#
        let cached = try JSONDecoder().decode(StoredAccount.self, from: Data(old.utf8))
        #expect(cached.account.limits == nil)
        #expect(cached.account.access == .trial)
    }
}
