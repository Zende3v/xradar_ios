import Foundation
import Testing
@testable import EonaCore

struct NearbyLabelsTests {
    /// Monday 14 September 2026, 20:40 in Paris.
    let now = parisMillis(2026, 9, 14, 20, 40)

    func status(_ state: OpenState, next: Int?, today: [TimeSlot] = [], alwaysOpen: Bool = false) -> NearbyLabels.Status? {
        NearbyLabels.status(OpeningHours(state: state, alwaysOpen: alwaysOpen, today: today, nextChangeMillis: next), nowMillis: now, timeZone: paris)
    }

    @Test func openStates() {
        #expect(status(.open, next: nil, alwaysOpen: true) == NearbyLabels.Status(text: "Ouvert", detail: "24 h/24", tone: .positive))
        #expect(status(.open, next: parisMillis(2026, 9, 14, 21, 0)) == NearbyLabels.Status(text: "Ferme bientôt", detail: "à 21:00", tone: .warning))
        #expect(status(.open, next: parisMillis(2026, 9, 14, 23, 0), today: [TimeSlot(from: "07:00", to: "23:00")])
            == NearbyLabels.Status(text: "Ouvert", detail: "07:00–23:00", tone: .positive))
    }

    @Test func closedStates() {
        #expect(status(.closed, next: parisMillis(2026, 9, 14, 22, 0)) == NearbyLabels.Status(text: "Fermé", detail: "ouvre à 22:00", tone: .negative))
        #expect(status(.closed, next: parisMillis(2026, 9, 15, 7, 0)) == NearbyLabels.Status(text: "Fermé", detail: "ouvre demain à 07:00", tone: .negative))
        #expect(status(.closed, next: parisMillis(2026, 9, 16, 9, 0)) == NearbyLabels.Status(text: "Fermé", detail: "ouvre mer. à 09:00", tone: .negative))
    }

    @Test func aPassedChangeFlipsTheState() {
        let hours = OpeningHours(state: .open, alwaysOpen: false, today: [], nextChangeMillis: parisMillis(2026, 9, 14, 20, 0))
        #expect(NearbyLabels.state(hours, nowMillis: now) == .closed)
        #expect(status(.open, next: parisMillis(2026, 9, 14, 20, 0)) == NearbyLabels.Status(text: "Fermé", detail: nil, tone: .negative))
    }

    @Test func unknownHoursShowTheirSlots() {
        let slots = [TimeSlot(from: "08:00", to: "12:00"), TimeSlot(from: "14:00", to: "18:00")]
        #expect(status(.unknown, next: nil, today: slots) == NearbyLabels.Status(text: "Horaires", detail: "08:00–12:00, 14:00–18:00", tone: .neutral))
        #expect(status(.unknown, next: nil) == nil)
        #expect(NearbyLabels.slots([TimeSlot(from: "00:00", to: "24:00")]) == "24 h/24")
    }

    @Test func detailsByKind() {
        let charger = place("c", meters: 10, nearby: NearbyInfo(charging: ChargingInfo(maxKw: 150, connectors: ["CCS", "Type 2"], points: 4)))
        #expect(NearbyLabels.details(charger) == ["150 kW", "CCS", "Type 2", "4 points"])

        let parking = place("p", meters: 10, nearby: NearbyInfo(parking: ParkingInfo(fee: false, type: .underground, capacity: 350, parkAndRide: true)))
        #expect(NearbyLabels.details(parking) == ["Gratuit", "Parking relais", "Souterrain", "350 places"])

        #expect(NearbyLabels.details(place("f", meters: 10, name: "Total Access", nearby: NearbyInfo(brand: "TotalEnergies"))) == ["TotalEnergies"])
        #expect(NearbyLabels.details(place("f", meters: 10, name: "TotalEnergies Rennes", nearby: NearbyInfo(brand: "Total Energies"))).isEmpty)
        #expect(NearbyLabels.details(place("h", meters: 10, nearby: NearbyInfo(customersOnly: true, stars: 3))) == ["★★★", "Clients"])
    }

    @Test func numbers() {
        #expect(NearbyLabels.kilowatts(7.4) == "7,4 kW")
        #expect(NearbyLabels.kilowatts(22) == "22 kW")
        #expect(NearbyLabels.distance(850) == "850 m")
        #expect(NearbyLabels.distance(1240) == "1,2 km")
        #expect(NearbyLabels.distance(12_400) == "12 km")
    }
}

struct NearbyPickerTests {
    let now = parisMillis(2026, 9, 14, 20, 40)

    var closed: OpeningHours {
        OpeningHours(state: .closed, alwaysOpen: false, today: [], nextChangeMillis: parisMillis(2026, 9, 15, 7, 0))
    }

    @Test func openFirstThenCloserClosedOnes() {
        let open = (1...25).map { place("o\($0)", meters: $0 * 100) }
        let shut = [place("c1", meters: 150, hours: closed), place("c2", meters: 2150, hours: closed)]
        let results = NearbyPicker.pick(Array((shut + open).reversed()), category: .parking, fuel: nil, nowMillis: now)
        #expect(results.open.map(\.id) == (1...20).map { "o\($0)" })
        #expect(results.closed.map(\.id) == ["c1"])
    }

    @Test func fewOpenPlacesStillListClosedOnes() {
        let open = (1...3).map { place("o\($0)", meters: $0 * 1000) }
        let shut = (1...10).map { place("c\($0)", meters: $0 * 100, hours: closed) }
        let results = NearbyPicker.pick(open + shut, category: .tobacco, fuel: nil, nowMillis: now)
        #expect(results.open.count == 3)
        #expect(results.closed.map(\.id) == (1...8).map { "c\($0)" })
    }

    @Test func pricedStationsGoAheadInACity() {
        let fresh = StationFuel(stationId: "x", matchedBy: "id", prices: [FuelPrice(type: .gazole, euros: 1.8, updatedAt: "2026-09-14T19:40:00+02:00")])
        let pool = (1...25).map { i in place("s\(i)", meters: i * 100, fuel: i == 21 || i == 22 ? fresh : nil) }
        let picked = FuelStationPicker.pick(pool, fuel: .gazole, nowMillis: now)
        // Priced stations first (the same price: nearest first), then the others, nearest first.
        #expect(picked.map(\.id) == ["s21", "s22"] + (1...18).map { "s\($0)" })
        #expect(NearbyPicker.pick(pool, category: .fuel, fuel: .gazole, nowMillis: now).open == picked)
    }

    @Test func aChosenFuelListsTheCheapestFirst() {
        let priced = { (euros: Double) in
            StationFuel(stationId: "x", matchedBy: "id", prices: [FuelPrice(type: .gazole, euros: euros, updatedAt: "2026-09-14T19:40:00+02:00")])
        }
        let pool = [
            place("near", meters: 100, fuel: priced(1.90)),
            place("none", meters: 200, fuel: nil),
            place("cheap", meters: 900, fuel: priced(1.70)),
            place("tie", meters: 300, fuel: priced(1.90)),
        ]
        #expect(FuelStationPicker.pick(pool, fuel: .gazole, nowMillis: now).map(\.id) == ["cheap", "near", "tie", "none"])
        // "Proche uniquement" (no fuel): nearest first, as before.
        #expect(FuelStationPicker.pick(pool, fuel: nil, nowMillis: now).map(\.id) == ["near", "none", "tie", "cheap"])
    }

    @Test func sparseAreasKeepTheNearest() {
        let fresh = StationFuel(stationId: "x", matchedBy: "id", prices: [FuelPrice(type: .gazole, euros: 1.8, updatedAt: "2026-09-14T19:40:00+02:00")])
        let pool = (1...25).map { i in place("s\(i)", meters: i * 1000, fuel: i == 25 ? fresh : nil) }
        #expect(FuelStationPicker.pick(pool, fuel: .gazole, nowMillis: now).map(\.id) == (1...20).map { "s\($0)" })
    }
}
