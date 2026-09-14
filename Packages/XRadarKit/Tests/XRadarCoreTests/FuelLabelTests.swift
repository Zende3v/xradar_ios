import Foundation
import Testing
@testable import XRadarCore

struct FuelLabelTests {
    @Test func pricesWithThreeDecimals() {
        #expect(FuelPrice(type: .gazole, euros: 2.283, updatedAt: nil).priceLabel == "2,283 €")
        #expect(FuelPrice(type: .gazole, euros: 1.9995, updatedAt: nil).priceLabel == "2,000 €")
        #expect(FuelPrice(type: .gazole, euros: 1.7, updatedAt: nil).priceLabel == "1,700 €")
        #expect(frenchOneDecimal(1.25) == "1,3")
    }

    @Test func priceAges() {
        let price = FuelPrice(type: .sp98, euros: 1.9, updatedAt: "2026-09-14T10:00:00+02:00")
        let at = parisMillis(2026, 9, 14, 10, 0)
        #expect(price.ageLabel(nowMillis: at + 30_000) == "à l'instant")
        #expect(price.ageLabel(nowMillis: at + 12 * 60_000) == "il y a 12 min")
        #expect(price.ageLabel(nowMillis: at + 3 * 3_600_000 + 5) == "il y a 3 h")
        #expect(price.ageLabel(nowMillis: at + 26 * 3_600_000) == "il y a 1 j")
        #expect(price.ageLabel(nowMillis: at - 60_000) == "à l'instant")
        #expect(FuelPrice(type: .sp98, euros: 1.9, updatedAt: nil).ageLabel(nowMillis: at) == nil)
    }
}
