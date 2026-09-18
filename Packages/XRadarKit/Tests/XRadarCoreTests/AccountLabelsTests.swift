import Foundation
import Testing
@testable import XRadarCore

private func member(_ role: Role, access: Access = .trial, canNavigate: Bool = true, endsAt: String? = nil) -> Account {
    Account(id: "a", role: role, username: "arthur", displayName: nil, avatarUrl: nil, email: nil, banned: false, access: access, canNavigate: canNavigate, accessEndsAt: endsAt)
}

struct AccountLabelsTests {
    @Test func accessLabels() {
        let now = parisMillis(2026, 9, 15, 12, 0)
        let formatter = ISO8601DateFormatter()
        let inDays = { (days: Double) in formatter.string(from: Date(millis: now + Int(days * 86_400_000))) }
        #expect(AccountLabels.access(nil, nowMillis: now) == "Invité")
        #expect(AccountLabels.access(member(.admin, access: .restricted), nowMillis: now) == "Admin")
        #expect(AccountLabels.access(member(.client, access: .restricted), nowMillis: now) == "Accès restreint")
        #expect(AccountLabels.access(member(.guest, canNavigate: false), nowMillis: now) == "Accès restreint")
        #expect(AccountLabels.access(member(.guest, endsAt: inDays(3.5)), nowMillis: now) == "Essai gratuit · 3 j restants")
        #expect(AccountLabels.access(member(.guest, endsAt: inDays(1.5)), nowMillis: now) == "Essai gratuit · dernier jour")
        #expect(AccountLabels.access(member(.guest), nowMillis: now) == "Essai gratuit · 7 j")
        #expect(AccountLabels.access(member(.client, access: .active, endsAt: "2027-03-12T10:00:00Z"), nowMillis: now, timeZone: paris) == "Membre · jusqu'au 12/03/2027")
        #expect(AccountLabels.access(member(.client, access: .active), nowMillis: now) == "Membre")
        #expect(AccountLabels.shortDate("pas une date") == "—")
    }

    @Test func usernameRulesAndNextChange() {
        #expect(UsernameRules.isWellFormed("arthur_35.x"))
        #expect(!UsernameRules.isWellFormed("ab"))
        #expect(!UsernameRules.isWellFormed("élodie"))
        #expect(!UsernameRules.isWellFormed("a b c"))
        #expect(!UsernameRules.isWellFormed(String(repeating: "a", count: 21)))
        let now = parisMillis(2026, 9, 18, 12, 0)
        let soon = Account(id: "a", role: .client, username: "x", displayName: nil, avatarUrl: nil, email: nil, banned: false,
                           canChangeUsername: true, usernameChangeableAt: "2026-09-25T10:00:00.000Z")
        #expect(AccountLabels.usernameChange(soon, nowMillis: now, timeZone: paris) == "Prochain changement le 25/09/2026")
        #expect(AccountLabels.usernameChange(soon, nowMillis: parisMillis(2026, 9, 26, 12, 0)) == nil)
        #expect(AccountLabels.usernameChange(member(.client), nowMillis: now) == nil)
        #expect(UsernameAvailability.fromWire(available: false, reason: "invalid username") == .invalid)
        #expect(UsernameAvailability.fromWire(available: false, reason: nil) == .taken)
    }

    @Test func trustToHalfStars() {
        #expect(AccountLabels.trustRounded(2.25) == 2.0)
        #expect(AccountLabels.trustRounded(2.8) == 3.0)
        #expect(AccountLabels.trustLabel(3.74) == "3,5")
        #expect(AccountLabels.trustLabel(2.5) == "2,5")
    }

    @Test func statsFigures() {
        #expect(StatsLabels.hours(seconds: 59 * 60) == "59 min")
        #expect(StatsLabels.hours(seconds: 125 * 60) == "2h05")
        #expect(StatsLabels.hours(seconds: 700 * 60) == "11h")
        #expect(StatsLabels.kilometers(meters: 9_450) == "9,5 km")
        #expect(StatsLabels.kilometers(meters: 12_345) == "12 km")
        #expect(StatsLabels.kilometers(meters: 3_240_500) == "3 240 km")
        #expect(StatsLabels.grouped(12) == "12")
        #expect(StatsLabels.grouped(1_234_567) == "1 234 567")
    }
}
