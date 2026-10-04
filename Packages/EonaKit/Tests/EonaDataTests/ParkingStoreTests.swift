import Foundation
import Testing
import EonaCore
@testable import EonaData

@MainActor
struct ParkingStoreTests {
    private func defaults() -> UserDefaults {
        let name = "parking-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    @Test func spotsSurviveRestartAndLeaveOneByOne() {
        let defaults = defaults()
        let parking = ParkingStore(defaults: defaults)
        #expect(parking.spots.isEmpty)
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let bike = parking.park(lat: 48.85, lon: 2.35, vehicle: .bicycle, at: at)
        let car = parking.park(lat: 48.80, lon: 2.40, vehicle: .car, at: at.addingTimeInterval(60))
        parking.setVehicle(.scooter, for: bike.id)
        let again = ParkingStore(defaults: defaults)
        #expect(again.spots.map(\.id) == [car.id, bike.id])
        #expect(again.spot(bike.id) == ParkingSpot(id: bike.id, lat: 48.85, lon: 2.35, parkedAt: at, vehicle: .scooter))
        again.remove(car.id)
        #expect(ParkingStore(defaults: defaults).spots.map(\.id) == [bike.id])
        for _ in 0..<20 { again.park(lat: 48, lon: 2, vehicle: .car) }
        #expect(again.spots.count == ParkingStore.limit)
        #expect(again.spot(bike.id) == nil)
    }

    @Test func singleSpotOfEarlierBuildsIsKept() {
        let defaults = defaults()
        defaults.set(["lat": 48.85, "lon": 2.35, "at": 1_790_000_000.0, "vehicle": "motorcycle"] as [String: Any], forKey: "xr_parking.spot")
        let parking = ParkingStore(defaults: defaults)
        #expect(parking.spots.count == 1)
        #expect(parking.spots.first?.vehicle == .motorcycle)
        #expect(defaults.object(forKey: "xr_parking.spot") == nil)
        #expect(ParkingStore(defaults: defaults).spots.map(\.id) == parking.spots.map(\.id))
    }

    @Test func ageLabels() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(ParkingSpot.ageLabel(since: now.addingTimeInterval(-20), now: now) == "à l'instant")
        #expect(ParkingSpot.ageLabel(since: now.addingTimeInterval(-12 * 60), now: now) == "il y a 12 min")
        #expect(ParkingSpot.ageLabel(since: now.addingTimeInterval(-3 * 3600), now: now) == "il y a 3 h")
        #expect(ParkingSpot.ageLabel(since: now.addingTimeInterval(-50 * 3600), now: now) == "il y a 2 j")
    }
}
