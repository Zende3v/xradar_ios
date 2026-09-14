import Foundation

/// The active route thinned to one point every couple of kilometres, with its padded bounding
/// box: enough to ask "is this alert on my trip?" thousands of times without cost.
public struct RouteCorridor: Sendable {
    /// Within this distance of the route or of the driver, an alert belongs to the trip.
    public static let radiusMeters = 15_000.0
    /// Spacing of the samples, well under the radius.
    static let stepMeters = 2_000.0

    let points: [GeoPoint]
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double

    public init(route: [GeoPoint]) {
        guard route.count >= 2 else {
            points = []
            minLat = 0
            maxLat = 0
            minLon = 0
            maxLon = 0
            return
        }
        var kept = [route[0]]
        var since = 0.0
        for i in 1..<route.count {
            since += Geo.haversine(lat1: route[i - 1].lat, lon1: route[i - 1].lon, lat2: route[i].lat, lon2: route[i].lon)
            if since >= Self.stepMeters {
                kept.append(route[i])
                since = 0
            }
        }
        kept.append(route[route.count - 1])
        points = kept
        let padLat = Self.radiusMeters / 111_000.0
        let padLon = padLat / max(cos(Geo.radians(kept[kept.count / 2].lat)), 0.1)
        minLat = kept.map(\.lat).min()! - padLat
        maxLat = kept.map(\.lat).max()! + padLat
        minLon = kept.map(\.lon).min()! - padLon
        maxLon = kept.map(\.lon).max()! + padLon
    }

    /// Worth showing during the trip: near the driver, or near the route itself (so the whole
    /// itinerary stays visible when the map is zoomed out).
    public func contains(lat: Double, lon: Double, driverLat: Double, driverLon: Double) -> Bool {
        if Geo.haversine(lat1: driverLat, lon1: driverLon, lat2: lat, lon2: lon) <= Self.radiusMeters { return true }
        guard !points.isEmpty else { return false }
        if lat < minLat || lat > maxLat || lon < minLon || lon > maxLon { return false }
        return points.contains { Geo.haversine(lat1: lat, lon1: lon, lat2: $0.lat, lon2: $0.lon) <= Self.radiusMeters }
    }
}
