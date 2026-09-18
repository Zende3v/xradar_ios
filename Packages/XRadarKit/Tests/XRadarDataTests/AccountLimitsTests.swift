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

    @Test func readsAndCachesTheUsernameChange() throws {
        let body = #"{"id":"c1","role":"client","access":"active","canChangeUsername":true,"usernameChangeableAt":"2026-09-25T10:00:00.000Z"}"#
        let client = AccountAPI.account(try object(body))
        #expect(client.canChangeUsername)
        #expect(client.usernameChangeableAt == "2026-09-25T10:00:00.000Z")
        let cached = try JSONDecoder().decode(StoredAccount.self, from: JSONEncoder().encode(StoredAccount(client)))
        #expect(cached.account.canChangeUsername)
        #expect(cached.account.usernameChangeableAt == client.usernameChangeableAt)
        #expect(!AccountAPI.account(try object(#"{"id":"a1","role":"admin"}"#)).canChangeUsername)
        #expect(AccountAPI.friendly("username reserved") == "Ce pseudo est réservé.")
        #expect(AccountAPI.friendly("username change too soon") == "Un seul changement de pseudo par semaine.")
    }

    @Test func usernameAvailabilityAsksWithTheSession() async throws {
        let transport = StubTransport(body: #"{"available":false,"reason":"reserved"}"#)
        #expect(await AccountAPI(client: backend(transport)).usernameAvailability("Admin_2", token: "t") == .reserved)
        #expect(transport.last?.query == ["u": "Admin_2"])
        #expect(transport.last?.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        #expect(await AccountAPI(client: backend(StubTransport(body: #"{"available":true,"reason":null}"#))).usernameAvailability("zoe", token: nil) == .available)
        #expect(await AccountAPI(client: backend(StubTransport(body: #"{"available":false,"reason":"taken"}"#))).usernameAvailability("zoe", token: nil) == .taken)
        #expect(await AccountAPI(client: backend(StubTransport(status: 502, body: ""))).usernameAvailability("zoe", token: nil) == nil)
    }

    @Test func aCacheFromBeforeLimitsStillReads() throws {
        let old = #"{"id":"u1","role":"guest","banned":false,"emailVerified":false,"access":"trial","canNavigate":true,"trust":2.5}"#
        let cached = try JSONDecoder().decode(StoredAccount.self, from: Data(old.utf8))
        #expect(cached.account.limits == nil)
        #expect(cached.account.access == .trial)
        #expect(!cached.account.canChangeUsername)
    }
}
