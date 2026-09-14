import Foundation
import Testing
@testable import XRadarCore

struct ModelTests {
    @Test func speedStatusAgainstTheLimit() {
        #expect(SpeedStatus.of(speedKmh: 50, limitKmh: nil) == nil)
        #expect(SpeedStatus.of(speedKmh: 51, limitKmh: 50) == .over)
        #expect(SpeedStatus.of(speedKmh: 47, limitKmh: 50) == .caution)
        #expect(SpeedStatus.of(speedKmh: 46, limitKmh: 50) == .safe)
    }

    @Test func radarKinds() {
        let redLight = Radar(id: "1", code: "etfr", vma: nil, lat: 0, lon: 0)
        #expect(redLight.alertType == .camera)
        #expect(redLight.displayTitle == "Radar feu rouge")
        #expect(Radar(id: "2", code: "ETF", vma: 80, lat: 0, lon: 0).alertType == .radarFixed)
    }

    @Test func accountFromTheWire() {
        #expect(Role.fromWire("admin") == .admin)
        #expect(Role.fromWire(nil) == .guest)
        #expect(Access.fromWire("restricted") == .restricted)
        #expect(Access.fromWire("?") == .trial)
        #expect(SpeedLimitChange.Status.fromWire("validated") == .validated)
        #expect(SpeedLimitChange.Status.fromWire("weird") == .closed)

        let account = Account(id: "a", role: .client, username: "  ", displayName: nil, avatarUrl: nil, email: nil, banned: false, canNavigate: false)
        #expect(!account.isOnboarded)
        #expect(account.isRestricted)
        #expect(account.canEditProfile)
    }

    @Test func tripLabels() {
        let now = Date(millis: parisMillis(2026, 9, 14, 12, 0))
        func trip(startedAt: Int, meters: Int = 12_345, seconds: Int = 3_900) -> TripRecord {
            TripRecord(id: "t", startedAt: startedAt, fromLabel: "", toLabel: "", distanceMeters: meters, durationSeconds: seconds, alertsCount: 0, topSpeedKmh: 0)
        }
        let today = trip(startedAt: parisMillis(2026, 9, 14, 8, 5))
        #expect(today.distanceLabel == "12 km")
        #expect(today.durationLabel == "1 h 05")
        #expect(today.dateLabel(now: now, timeZone: paris) == "Aujourd'hui · 08:05")
        #expect(trip(startedAt: parisMillis(2026, 9, 13, 18, 30)).dateLabel(now: now, timeZone: paris) == "Hier · 18:30")
        #expect(trip(startedAt: parisMillis(2026, 9, 10, 8, 5)).dateLabel(now: now, timeZone: paris) == "10 sept. · 08:05")
        #expect(trip(startedAt: 0, meters: 3_456, seconds: 2_700).distanceLabel == "3,5 km")
        #expect(trip(startedAt: 0, meters: 3_456, seconds: 2_700).durationLabel == "45 min")
    }

    @Test func fuelPriceFreshness() {
        let now = parisMillis(2026, 9, 14, 20, 40)
        let price = FuelPrice(type: .gazole, euros: 1.759, updatedAt: "2026-09-14T09:29:05+02:00")
        #expect(price.updatedAtMillis == parisMillis(2026, 9, 14, 9, 29) + 5_000)
        #expect(price.isFresh(nowMillis: now))
        #expect(!price.isFresh(nowMillis: now + FuelPrice.freshMillis))
        #expect(!FuelPrice(type: .e10, euros: 1.7, updatedAt: nil).isFresh(nowMillis: now))
        #expect(FuelPrice(type: .e10, euros: 1.7, updatedAt: "hier").updatedAtMillis == nil)

        let station = StationFuel(stationId: "1", matchedBy: "id", prices: [
            price,
            FuelPrice(type: .e10, euros: 1.7, updatedAt: "2026-09-14T09:29:05+02:00", outOfStock: true),
        ])
        #expect(place("s", meters: 100, fuel: station).showsFuelPrice(.gazole, nowMillis: now))
        #expect(!place("s", meters: 100, fuel: station).showsFuelPrice(.e10, nowMillis: now))
    }
}
