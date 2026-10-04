import Foundation
import Observation
import EonaCore

/// « Stationnement » : plusieurs repères, gardés sur ce téléphone (UserDefaults), jamais envoyés.
@MainActor
@Observable
public final class ParkingStore {
    /// Plus récent d'abord.
    public private(set) var spots: [ParkingSpot]

    /// Repères au plus : le plus ancien part au-delà.
    public static let limit = 10

    private let defaults: UserDefaults
    private static let key = "xr_parking.spots"
    /// Repère unique des builds 26 et 27.
    private static let legacyKey = "xr_parking.spot"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        spots = Self.read(defaults)
    }

    public func spot(_ id: String) -> ParkingSpot? {
        spots.first { $0.id == id }
    }

    /// Repère posé ici, maintenant, en tête de liste.
    @discardableResult
    public func park(lat: Double, lon: Double, vehicle: ParkedVehicle, at date: Date = Date()) -> ParkingSpot {
        let spot = ParkingSpot(lat: lat, lon: lon, parkedAt: date, vehicle: vehicle)
        save(Array(([spot] + spots).prefix(Self.limit)))
        return spot
    }

    public func setVehicle(_ vehicle: ParkedVehicle, for id: String) {
        guard let index = spots.firstIndex(where: { $0.id == id }) else { return }
        var updated = spots
        updated[index].vehicle = vehicle
        save(updated)
    }

    public func remove(_ id: String) {
        save(spots.filter { $0.id != id })
    }

    private func save(_ value: [ParkingSpot]) {
        spots = value
        defaults.set(Self.encoded(value), forKey: Self.key)
    }

    /// Liste gardée, ou repère unique d'avant, repris une fois. Entrée illisible : écartée.
    private static func read(_ defaults: UserDefaults) -> [ParkingSpot] {
        if let list = defaults.array(forKey: key) as? [[String: Any]] {
            return list.compactMap { spot(from: $0) }
        }
        guard let legacy = defaults.dictionary(forKey: legacyKey) else { return [] }
        defaults.removeObject(forKey: legacyKey)
        let spots = spot(from: legacy).map { [$0] } ?? []
        defaults.set(encoded(spots), forKey: key)
        return spots
    }

    private static func encoded(_ spots: [ParkingSpot]) -> [[String: Any]] {
        spots.map { spot in
            [
                "id": spot.id, "lat": spot.lat, "lon": spot.lon,
                "at": spot.parkedAt.timeIntervalSince1970, "vehicle": spot.vehicle.rawValue,
            ] as [String: Any]
        }
    }

    private static func spot(from stored: [String: Any]) -> ParkingSpot? {
        guard let lat = stored["lat"] as? Double, let lon = stored["lon"] as? Double, let at = stored["at"] as? Double,
              abs(lat) <= 90, abs(lon) <= 180
        else { return nil }
        let vehicle = ParkedVehicle(rawValue: stored["vehicle"] as? String ?? "") ?? .car
        let id = (stored["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        return ParkingSpot(id: id, lat: lat, lon: lon, parkedAt: Date(timeIntervalSince1970: at), vehicle: vehicle)
    }
}
