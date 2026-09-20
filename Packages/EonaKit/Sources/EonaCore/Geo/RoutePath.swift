import Foundation

/// A polyline with cumulative distances, for map-matching the driver to the route: snap the GPS
/// fix onto the line, know how far along it we are, read the pose at a given distance, and trim
/// the part already driven ("the arrow eats the line"). Equirectangular metres.
public struct RoutePath: Sendable {
    public let points: [GeoPoint]
    public let totalMeters: Double
    private let cumulative: [Double]

    /// Snapped point, distance along the route, off-route distance, and route bearing.
    public struct Match: Sendable, Hashable {
        public let lat: Double
        public let lon: Double
        public let alongMeters: Double
        public let offRouteMeters: Double
        public let bearingDeg: Double
    }

    public init(points: [GeoPoint]) {
        self.points = points
        var cumulative = [Double](repeating: 0, count: points.count)
        for i in points.indices.dropFirst() {
            let a = points[i - 1]
            let b = points[i]
            cumulative[i] = cumulative[i - 1] + Geo.haversine(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon)
        }
        self.cumulative = cumulative
        totalMeters = cumulative.last ?? 0
    }

    /// Nearest point on the route to (lat, lon). Full scan: call at GPS rate, not per frame.
    public func match(lat: Double, lon: Double) -> Match? {
        guard points.count >= 2 else { return nil }
        let metersPerLat = 111_320.0
        let metersPerLon = 111_320.0 * cos(Geo.radians(lat))
        let px = lon * metersPerLon
        let py = lat * metersPerLat
        var best = Double.greatestFiniteMagnitude
        var bestIndex = 0
        var bestT = 0.0
        var bestX = 0.0
        var bestY = 0.0
        for i in 0..<(points.count - 1) {
            let ax = points[i].lon * metersPerLon
            let ay = points[i].lat * metersPerLat
            let dx = points[i + 1].lon * metersPerLon - ax
            let dy = points[i + 1].lat * metersPerLat - ay
            let length2 = dx * dx + dy * dy
            let projected = ((px - ax) * dx + (py - ay) * dy) / length2
            let t = length2 == 0 ? 0.0 : min(max(projected, 0.0), 1.0)
            let sx = ax + t * dx
            let sy = ay + t * dy
            let d2 = (px - sx) * (px - sx) + (py - sy) * (py - sy)
            if d2 < best {
                best = d2
                bestIndex = i
                bestT = t
                bestX = sx
                bestY = sy
            }
        }
        let snapLat = bestY / metersPerLat
        let snapLon = bestX / metersPerLon
        let segment = cumulative[bestIndex + 1] - cumulative[bestIndex]
        let a = points[bestIndex]
        let b = points[bestIndex + 1]
        return Match(
            lat: snapLat,
            lon: snapLon,
            alongMeters: cumulative[bestIndex] + bestT * segment,
            offRouteMeters: Geo.haversine(lat1: lat, lon1: lon, lat2: snapLat, lon2: snapLon),
            bearingDeg: Geo.bearing(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon)
        )
    }

    /// Interpolated point and route bearing at a cumulative distance.
    public func pose(at distanceMeters: Double) -> (point: GeoPoint, bearingDeg: Double) {
        guard points.count >= 2 else { return (points.first ?? GeoPoint(lat: 0, lon: 0), 0) }
        let d = min(max(distanceMeters, 0), totalMeters)
        let i = segmentIndex(for: d)
        let segment = cumulative[i + 1] - cumulative[i]
        let t = segment <= 0 ? 0.0 : min(max((d - cumulative[i]) / segment, 0.0), 1.0)
        let a = points[i]
        let b = points[i + 1]
        let point = GeoPoint(lat: a.lat + (b.lat - a.lat) * t, lon: a.lon + (b.lon - a.lon) * t)
        return (point, Geo.bearing(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon))
    }

    /// Remaining route from a distance to the end (the part still ahead of the driver).
    public func trimmed(from distanceMeters: Double) -> [GeoPoint] {
        guard points.count >= 2 else { return points }
        let d = min(max(distanceMeters, 0), totalMeters)
        let i = segmentIndex(for: d)
        return [pose(at: d).point] + points[(i + 1)...]
    }

    private func segmentIndex(for d: Double) -> Int {
        var low = 0
        var high = points.count - 2
        while low < high {
            let mid = (low + high + 1) / 2
            if cumulative[mid] <= d {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}
