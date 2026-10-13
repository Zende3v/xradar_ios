import Foundation
import Testing
@testable import EonaData
import EonaCore

struct FuelStationSearchTests {
    @Test func emptySearchReachesFiftyKilometres() async throws {
        let probe = FuelSearchProbe(replies: [[], [], []])
        let result = try #require(await PlacesAPI.nearFuel(cashOnly: false) { await probe.load($0) })
        #expect(result.places.isEmpty)
        #expect(result.radiusM == 50_000)
        #expect(await probe.radii == [10_000, 25_000, 50_000])
    }

    @Test func aClosedStationWithoutPricesStopsExpansion() async throws {
        let station = Self.station("closed", meters: 9000, closed: true)
        let probe = FuelSearchProbe(replies: [[station], []])
        let result = try #require(await PlacesAPI.nearFuel(cashOnly: false) { await probe.load($0) })
        #expect(result.places == [station])
        #expect(result.radiusM == 10_000)
        #expect(await probe.radii == [10_000])
    }

    @Test func firstResultAtTwentyFiveKilometresStopsExpansion() async throws {
        let station = Self.station("station", meters: 18_000)
        let probe = FuelSearchProbe(replies: [[], [station], []])
        let result = try #require(await PlacesAPI.nearFuel(cashOnly: false) { await probe.load($0) })
        #expect(result.places == [station])
        #expect(result.radiusM == 25_000)
        #expect(await probe.radii == [10_000, 25_000])
    }

    @Test func ignoredBackendFiltersStillRequireCashAndRadius() async throws {
        let cash = Self.station("cash", meters: 30_000, accepted: true)
        let unknown = Self.station("unknown", meters: 100)
        let card = Self.station("card", meters: 200, accepted: false)
        let invalidDistance = Self.station("invalid", meters: -1, accepted: true)
        let pool = [unknown, card, invalidDistance, cash]
        let probe = FuelSearchProbe(replies: [pool, pool, pool])
        let result = try #require(await PlacesAPI.nearFuel(cashOnly: true) { await probe.load($0) })
        #expect(result.places == [cash])
        #expect(result.radiusM == 50_000)
        #expect(await probe.radii == [10_000, 25_000, 50_000])
    }

    @Test func failedSearchStopsExpansion() async {
        let probe = FuelSearchProbe(replies: [[], nil, []])
        let result = await PlacesAPI.nearFuel(cashOnly: false) { await probe.load($0) }
        #expect(result == nil)
        #expect(await probe.radii == [10_000, 25_000])
    }

    @Test func cancellationStopsBeforeNextRadius() async {
        let probe = FuelSearchProbe(replies: [[], [], []])
        let task = Task {
            await PlacesAPI.nearFuel(cashOnly: false) { radiusM in
                let result = await probe.load(radiusM)
                withUnsafeCurrentTask { $0?.cancel() }
                return result
            }
        }
        #expect(await task.value == nil)
        #expect(await probe.radii == [10_000])
    }

    private static func station(_ id: String, meters: Int, accepted: Bool? = nil, closed: Bool = false) -> Place {
        Place(
            id: id, name: id, subtitle: "", kind: .result, lat: 48.1, lon: 2.1,
            distanceMeters: meters,
            nearby: closed ? NearbyInfo(hours: OpeningHours(state: .closed, alwaysOpen: false, today: [], nextChangeMillis: nil)) : nil,
            cashPayment: CashPayment(accepted: accepted, source: accepted == nil ? nil : "osm")
        )
    }
}

private actor FuelSearchProbe {
    let replies: [[Place]?]
    private(set) var radii: [Int] = []

    init(replies: [[Place]?]) {
        self.replies = replies
    }

    func load(_ radiusM: Int) -> [Place]? {
        radii.append(radiusM)
        let index = radii.count - 1
        return index < replies.count ? replies[index] : nil
    }
}
