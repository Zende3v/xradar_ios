import Foundation
import Observation
import EonaCore

/// « Garer mon véhicule » : un repère, gardé sur ce téléphone (UserDefaults), jamais envoyé.
@MainActor
@Observable
public final class ParkingStore {
    public private(set) var spot: ParkingSpot?

    private let defaults: UserDefaults
    private static let key = "xr_parking.spot"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        spot = Self.read(defaults)
    }

    /// Repère posé ici, maintenant ; remplace le précédent.
    public func park(lat: Double, lon: Double, vehicle: ParkedVehicle, at date: Date = Date()) {
        save(ParkingSpot(lat: lat, lon: lon, parkedAt: date, vehicle: vehicle))
    }

    public func setVehicle(_ vehicle: ParkedVehicle) {
        guard var current = spot else { return }
        current.vehicle = vehicle
        save(current)
    }

    public func clear() {
        spot = nil
        defaults.removeObject(forKey: Self.key)
    }

    private func save(_ value: ParkingSpot) {
        spot = value
        defaults.set([
            "lat": value.lat, "lon": value.lon, "at": value.parkedAt.timeIntervalSince1970, "vehicle": value.vehicle.rawValue,
        ] as [String: Any], forKey: Self.key)
    }

    /// Valeur gardée ; illisible : aucun repère.
    private static func read(_ defaults: UserDefaults) -> ParkingSpot? {
        guard let stored = defaults.dictionary(forKey: key),
              let lat = stored["lat"] as? Double, let lon = stored["lon"] as? Double, let at = stored["at"] as? Double,
              abs(lat) <= 90, abs(lon) <= 180
        else { return nil }
        let vehicle = ParkedVehicle(rawValue: stored["vehicle"] as? String ?? "") ?? .car
        return ParkingSpot(lat: lat, lon: lon, parkedAt: Date(timeIntervalSince1970: at), vehicle: vehicle)
    }
}
