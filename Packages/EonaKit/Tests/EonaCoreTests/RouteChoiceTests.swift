import Foundation
import Testing
@testable import EonaCore

struct RouteChoiceTests {
    private let place = Place(id: "p", name: "Tour Eiffel", subtitle: "Paris", kind: .result, lat: 48.858, lon: 2.294)

    private func route(meters: Int, seconds: Int, traffic: Int? = nil) -> Route {
        Route(points: [GeoPoint(lat: 0, lon: 0), GeoPoint(lat: 0, lon: 1)], distanceMeters: meters, durationSeconds: seconds, trafficSeconds: traffic)
    }

    @Test func timeShownIsHereWhenKnown() {
        #expect(route(meters: 1000, seconds: 600, traffic: 900).expectedSeconds == 900)
        #expect(route(meters: 1000, seconds: 600).expectedSeconds == 600)
        #expect(RouteChoiceText.duration(20) == "1 min")
        #expect(RouteChoiceText.duration(1860) == "31 min")
        #expect(RouteChoiceText.duration(3900) == "1 h 05")
        #expect(RouteChoiceText.arrival(route(meters: 1000, seconds: 600, traffic: 1800), now: Date(timeIntervalSince1970: 0), timeZone: TimeZone(identifier: "UTC")!) == "00:30")
    }

    @Test func ecoSaysWhatItSavesAndCosts() {
        let fast = route(meters: 24_800, seconds: 1500, traffic: 1800)
        let eco = route(meters: 21_600, seconds: 1700, traffic: 2040)
        #expect(RouteChoiceText.eco(eco, against: fast) == "+4 min · −3,2 km")
        #expect(RouteChoiceText.fastest(fast, against: eco) == "4 min gagnées")
        #expect(RouteChoiceText.eco(route(meters: 21_600, seconds: 1500, traffic: 1790), against: fast) == "Aussi rapide · −3,2 km")
        // 6,5 L/100 km à 1,80 €/L : 24,8 km = 2,90 € ; 3,2 km économisés = 0,37 €.
        let fuel = FuelEstimate(litresPer100: 6.5, eurosPerLitre: 1.8)
        #expect(RouteChoiceText.fastest(fast, against: eco, fuel: fuel) == "4 min gagnées · ≈ 2,90 €")
        #expect(RouteChoiceText.eco(eco, against: fast, fuel: fuel) == "+4 min · −3,2 km · −0,37 €")
        #expect(RouteChoiceText.roads(RouteRoads(toll: true, motorway: true, ferry: false)) == "Autoroute · Péage")
        #expect(RouteChoiceText.roads(RouteRoads(toll: false, motorway: false, ferry: false)) == "Sans autoroute ni péage")
        #expect(RouteChoiceText.roads(nil) == nil)
        #expect(RouteChoiceText.eco(eco, against: nil) == "Le plus court en distance")
        // Même tracé à 1 % près : un seul trajet.
        let twin = route(meters: 24_700, seconds: 1500, traffic: 1810)
        #expect(RouteChoiceText.eco(twin, against: fast) == "Même trajet que Rapide")
        #expect(RouteChoiceText.fastest(fast, against: twin) == "Bouchons évités en route")
    }

    @Test func fuelPriceIsTheMedianOfFreshPrices() {
        let now = 1_790_000_000_000
        let fresh = "2026-09-21T10:00:00+02:00"
        func station(_ id: String, _ prices: [FuelPrice]) -> Place {
            Place(id: id, name: id, subtitle: "", kind: .result, lat: 0, lon: 0, fuel: StationFuel(stationId: id, matchedBy: "id", prices: prices))
        }
        let places = [
            station("a", [FuelPrice(type: .gazole, euros: 1.70, updatedAt: fresh)]),
            station("b", [FuelPrice(type: .gazole, euros: 1.90, updatedAt: fresh)]),
            station("c", [FuelPrice(type: .gazole, euros: 1.80, updatedAt: fresh), FuelPrice(type: .e85, euros: 0.80, updatedAt: fresh)]),
            station("d", [FuelPrice(type: .gazole, euros: 1.20, updatedAt: fresh, outOfStock: true)]),
        ]
        #expect(FuelEstimate.medianPrice(.gazole, in: places, nowMillis: now) == 1.80)
        #expect(FuelEstimate.medianPrice(.e85, in: places, nowMillis: now) == 0.80)
        #expect(FuelEstimate.medianPrice(.gplc, in: places, nowMillis: now) == nil)
    }

    @Test func fastestKeepsLeastTimeWithTraffic() {
        // Capture Arthur 04/10 : Rapide 11 km 37 min, Éco 9,6 km 34 min, temps HERE.
        var choice = RouteChoice(destination: place)
        choice.fastest = .ready(route(meters: 11_000, seconds: 1500, traffic: 2220))
        choice.shortest = .ready(route(meters: 9_600, seconds: 1560, traffic: 2040))
        choice.keepFastestByTraffic()
        #expect(choice.fastest.route?.distanceMeters == 9_600)
        #expect(RouteChoiceText.eco(choice.shortest.route!, against: choice.fastest.route) == "Même trajet que Rapide")
        // Un temps HERE manque : sources différentes, rien changé.
        var mixed = RouteChoice(destination: place)
        mixed.fastest = .ready(route(meters: 11_000, seconds: 1500))
        mixed.shortest = .ready(route(meters: 9_600, seconds: 1560, traffic: 1400))
        mixed.keepFastestByTraffic()
        #expect(mixed.fastest.route?.distanceMeters == 11_000)
        #expect(RouteChoiceText.eco(route(meters: 9_600, seconds: 1560, traffic: 2040), against: route(meters: 11_000, seconds: 1500, traffic: 2220)) == "−3 min · −1,4 km")
    }

    @Test func choiceStatesAndSelection() {
        var choice = RouteChoice(destination: place)
        #expect(choice.loading)
        #expect(choice.chosenRoute == nil)
        #expect(choice.selected == .fastest)
        choice.fastest = .unavailable
        choice.shortest = .ready(route(meters: 1000, seconds: 120))
        choice.keepUsableSelection()
        #expect(choice.selected == .shortest)
        #expect(choice.chosenRoute?.distanceMeters == 1000)
        #expect(!choice.failed)
        choice.shortest = .unavailable
        #expect(choice.failed)
        #expect(!choice.loading)
    }
}

struct SeededEtaTests {
    @Test func choiceTimeIsTheEtaFromTheStart() throws {
        let points = [GeoPoint(lat: 48.8, lon: 2.3), GeoPoint(lat: 48.8, lon: 2.4)]
        let meters = RoutePath(points: points).totalMeters
        // Valhalla 6 min, HERE avec trafic 13 min : ETA départ = 13 min.
        let route = Route(points: points, distanceMeters: Int(meters), durationSeconds: 360, trafficSeconds: 780)
        let parts = try #require(TrafficParts.seeded(by: route, routeMeters: meters))
        let left = EtaEstimator.secondsLeft(route: route, routeMeters: meters, alongMeters: 0, traffic: parts.merged())
        #expect(abs(left - 780) < 1)
        #expect(abs(EtaEstimator.secondsLeft(route: route, routeMeters: meters, alongMeters: meters / 2, traffic: parts.merged()) - 390) < 1)
        // Sans temps HERE : rien, ETA moteur comme avant.
        #expect(TrafficParts.seeded(by: Route(points: points, distanceMeters: 1, durationSeconds: 360), routeMeters: meters) == nil)
    }
}
