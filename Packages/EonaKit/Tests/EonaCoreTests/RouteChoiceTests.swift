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
        #expect(RouteChoiceText.eco(eco, against: fast) == "3,2 km de moins · 4 min de plus")
        #expect(RouteChoiceText.fastest(fast, against: eco) == "4 min de moins · bouchons évités")
        #expect(RouteChoiceText.eco(route(meters: 21_600, seconds: 1500, traffic: 1790), against: fast) == "3,2 km de moins · aussi rapide")
        #expect(RouteChoiceText.eco(eco, against: nil) == "Le plus court en distance")
        // Même tracé à 1 % près : un seul trajet.
        let twin = route(meters: 24_700, seconds: 1500, traffic: 1810)
        #expect(RouteChoiceText.eco(twin, against: fast) == "Même trajet que Rapide")
        #expect(RouteChoiceText.fastest(fast, against: twin) == "Bouchons évités en route")
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
