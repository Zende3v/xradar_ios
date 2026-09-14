import Foundation

/// A lat/lon coordinate.
public struct GeoPoint: Sendable, Hashable {
    public let lat: Double
    public let lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

/// Geo helpers, in metres and degrees.
public enum Geo {
    static let earthRadiusMeters = 6_371_000.0

    /// Great-circle distance in metres.
    public static func haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let halfDLat = radians(lat2 - lat1) / 2.0
        let halfDLon = radians(lon2 - lon1) / 2.0
        let latTerm = sin(halfDLat) * sin(halfDLat)
        let lonTerm = cos(radians(lat1)) * cos(radians(lat2)) * sin(halfDLon) * sin(halfDLon)
        return 2.0 * earthRadiusMeters * asin(min(1.0, (latTerm + lonTerm).squareRoot()))
    }

    /// Initial bearing from point 1 to point 2, in degrees (0..<360, clockwise from north).
    public static func bearing(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let phi1 = radians(lat1)
        let phi2 = radians(lat2)
        let dLon = radians(lon2 - lon1)
        let y = sin(dLon) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLon)
        return (degrees(atan2(y, x)) + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    /// Smallest angle between two bearings (0...180).
    public static func angularDiff(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360.0)
        return d > 180.0 ? 360.0 - d : d
    }

    static func radians(_ degrees: Double) -> Double {
        degrees / 180.0 * Double.pi
    }

    static func degrees(_ radians: Double) -> Double {
        radians * 180.0 / Double.pi
    }
}
