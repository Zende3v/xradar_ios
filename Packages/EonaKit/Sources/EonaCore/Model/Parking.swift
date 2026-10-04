import Foundation

/// Véhicule garé : ce que montre le repère.
public enum ParkedVehicle: String, Sendable, Hashable, CaseIterable {
    case car
    case motorcycle
    case bicycle
    case scooter

    public var label: String {
        switch self {
        case .car: "Voiture"
        case .motorcycle: "Moto"
        case .bicycle: "Vélo"
        case .scooter: "Trottinette"
        }
    }
}

/// Repère de stationnement : position fixe, heure, véhicule. Gardé sur ce téléphone seulement.
public struct ParkingSpot: Sendable, Hashable {
    public let lat: Double
    public let lon: Double
    public let parkedAt: Date
    public var vehicle: ParkedVehicle

    public init(lat: Double, lon: Double, parkedAt: Date, vehicle: ParkedVehicle) {
        self.lat = lat
        self.lon = lon
        self.parkedAt = parkedAt
        self.vehicle = vehicle
    }

    /// "à l'instant", "il y a 12 min", "il y a 3 h", "il y a 2 j".
    public static func ageLabel(since date: Date, now: Date = Date()) -> String {
        let minutes = max(Int(now.timeIntervalSince(date) / 60), 0)
        if minutes < 1 { return "à l'instant" }
        if minutes < 60 { return "il y a \(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "il y a \(hours) h" }
        return "il y a \(hours / 24) j"
    }
}
