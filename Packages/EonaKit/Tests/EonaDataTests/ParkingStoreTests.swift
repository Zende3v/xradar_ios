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

    @Test func spotSurvivesRestartAndCanBeCleared() {
        let defaults = defaults()
        let parking = ParkingStore(defaults: defaults)
        #expect(parking.spot == nil)
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        parking.park(lat: 48.85, lon: 2.35, vehicle: .bicycle, at: at)
        parking.setVehicle(.scooter)
        let again = ParkingStore(defaults: defaults)
        #expect(again.spot == ParkingSpot(lat: 48.85, lon: 2.35, parkedAt: at, vehicle: .scooter))
        again.clear()
        #expect(ParkingStore(defaults: defaults).spot == nil)
    }

    @Test func ageLabels() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(ParkingSpot.ageLabel(since: now.addingTimeInterval(-20), now: now) == "à l'instant")
        #expect(ParkingSpot.ageLabel(since: now.addingTimeInterval(-12 * 60), now: now) == "il y a 12 min")
        #expect(ParkingSpot.ageLabel(since: now.addingTimeInterval(-3 * 3600), now: now) == "il y a 3 h")
        #expect(ParkingSpot.ageLabel(since: now.addingTimeInterval(-50 * 3600), now: now) == "il y a 2 j")
    }
}
