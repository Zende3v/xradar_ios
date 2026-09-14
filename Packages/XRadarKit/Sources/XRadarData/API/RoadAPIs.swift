import Foundation
import XRadarCore

/// The limit on the road under the driver ([kmh] nil = not mapped), and that road's id.
public struct RoadLimit: Sendable, Hashable {
    public let kmh: Int?
    public let wayId: String?

    public init(kmh: Int?, wayId: String?) {
        self.kmh = kmh
        self.wayId = wayId
    }
}

/// OSM road signs and limits (`/api/signs`).
public struct SignAPI: Sendable {
    static let timeout: TimeInterval = 25

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    public func near(lat: Double, lon: Double, radiusM: Int) async -> [RoadSign] {
        let query = [URLQueryItem("lat", lat), URLQueryItem("lon", lon), URLQueryItem("radius", radiusM)]
        guard let result = try? await client.send(client.request("GET", client.url("/api/signs/near", query: query), timeout: Self.timeout)) else {
            return []
        }
        return Self.signs(result.json)
    }

    /// Every sign along the whole route ([points] as the polyline).
    public func route(_ points: [GeoPoint]) async -> [RoadSign] {
        guard points.count >= 2,
              let result = try? await client.send(client.request(
                  "POST", client.url("/api/signs/route"), json: ["coordinates": coordinates(points)], timeout: Self.timeout
              ))
        else { return [] }
        return Self.signs(result.json)
    }

    /// Speed limit where the driver is, for the way they go: the backend picks the road by
    /// distance, [bearingDeg] (their course) and continuity with [previousWayId] (the road the
    /// previous answer gave). Nil when the request failed.
    public func limit(lat: Double, lon: Double, bearingDeg: Double? = nil, previousWayId: String? = nil) async -> RoadLimit? {
        var query = [URLQueryItem("lat", lat), URLQueryItem("lon", lon)]
        if let bearingDeg { query.append(URLQueryItem("bearing", bearingDeg)) }
        if let previousWayId { query.append(URLQueryItem("way", previousWayId)) }
        guard let result = try? await client.send(client.request("GET", client.url("/api/signs/limit", query: query), timeout: Self.timeout)),
              result.isSuccessful,
              let json = result.json
        else { return nil }
        let kmh = json.isNull("v") ? nil : json.int("v")
        return RoadLimit(kmh: kmh.flatMap { (5...130).contains($0) ? $0 : nil }, wayId: json.nonBlankString("way"))
    }

    static func signs(_ json: JSON?) -> [RoadSign] {
        (json?.objects("signs") ?? []).compactMap { o in
            guard let type = SignType(rawValue: o.string("type")) else { return nil }
            return RoadSign(type: type, lat: o.double("lat"), lon: o.double("lon"), speed: o.has("v") ? o.int("v") : nil)
        }
    }
}

/// Driving routes (`/api/route`, OpenRouteService or OSRM behind it).
public struct RoutingAPI: Sendable {
    static let timeout: TimeInterval = 15

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    /// [avoid] holds "tolls" and/or "highways". The backend refuses a restricted account, so
    /// the session [token] goes along.
    public func route(from: GeoPoint, to: GeoPoint, avoid: [String] = [], token: String?) async throws -> Route? {
        var query = [URLQueryItem("from", "\(from.lat),\(from.lon)"), URLQueryItem("to", "\(to.lat),\(to.lon)")]
        if !avoid.isEmpty { query.append(URLQueryItem("avoid", avoid.joined(separator: ","))) }
        let result = try await client.send(client.request("GET", client.url("/api/route", query: query), token: token, timeout: Self.timeout))
        guard result.isSuccessful, let json = result.json else { return nil }
        return Self.route(json)
    }

    static func route(_ json: JSON) -> Route? {
        // The backend sends [longitude, latitude].
        let points = (json.array("coordinates") ?? []).compactMap { JSON.lonLat($0) }
        guard points.count >= 2 else { return nil }
        let steps = (json.objects("steps") ?? []).compactMap { s -> RouteStep? in
            guard let location = JSON.lonLat(s.raw["location"]) else { return nil }
            return RouteStep(
                location: location,
                type: s.string("type"),
                modifier: s.nonBlankString("modifier"),
                name: s.string("name"),
                distanceMeters: s.int("distanceM"),
                exit: s.isNull("exit") ? nil : s.int("exit")
            )
        }
        return Route(points: points, distanceMeters: json.int("distanceM"), durationSeconds: json.int("durationS"), steps: steps)
    }
}

/// Fixed radars (`/api/radars`).
public struct RadarAPI: Sendable {
    static let timeout: TimeInterval = 8

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    /// Radars within [radiusM] of a point; nil when the request failed (not "no radars").
    public func near(lat: Double, lon: Double, radiusM: Int) async throws -> [Radar]? {
        let query = [URLQueryItem("lat", lat), URLQueryItem("lon", lon), URLQueryItem("radius", radiusM)]
        let result = try await client.send(client.request("GET", client.url("/api/radars/near", query: query), timeout: Self.timeout))
        guard result.isSuccessful, let json = result.json else { return nil }
        return Self.radars(json)
    }

    /// Radars on the trip, within the backend's buffer of the route polyline. Nil when the request
    /// failed, so the caller can fall back to the ring around the driver.
    public func route(_ points: [GeoPoint]) async throws -> [Radar]? {
        guard points.count >= 2 else { return [] }
        let request = try client.request("POST", client.url("/api/radars/route"), json: ["coordinates": coordinates(points)], timeout: Self.timeout)
        let result = try await client.send(request)
        guard result.isSuccessful, let json = result.json else { return nil }
        return Self.radars(json)
    }

    static func radars(_ json: JSON) -> [Radar] {
        (json.objects("radars") ?? []).map { o in
            Radar(id: o.string("id"), code: o.string("type"), vma: o.isNull("vma") ? nil : o.int("vma"), lat: o.double("lat"), lon: o.double("lon"))
        }
    }
}

/// A limit proposal to post: the limit the sign shows, where, and what the HUD showed.
public struct NewSpeedLimitReport: Sendable, Hashable {
    public let lat: Double
    public let lon: Double
    /// The driver's course: a sign only applies to the way it faces.
    public let bearingDeg: Double?
    public let displayedKmh: Int?
    public let displayedSource: SpeedLimitSource?
    public let newKmh: Int

    public init(lat: Double, lon: Double, bearingDeg: Double?, displayedKmh: Int?, displayedSource: SpeedLimitSource?, newKmh: Int) {
        self.lat = lat
        self.lon = lon
        self.bearingDeg = bearingDeg
        self.displayedKmh = displayedKmh
        self.displayedSource = displayedSource
        self.newKmh = newKmh
    }
}

/// Speed-limit maintenance (`/api/speed-limits`).
public struct SpeedLimitAPI: Sendable {
    static let timeout: TimeInterval = 8

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    /// Where the proposal stands; nil when refused, or when it confirmed a limit nobody questioned.
    public func report(_ report: NewSpeedLimitReport, token: String?, deviceId: String?) async throws -> SpeedLimitChange? {
        var payload: [String: Any] = ["lat": report.lat, "lon": report.lon, "newKmh": report.newKmh]
        if let bearing = report.bearingDeg { payload["bearing"] = bearing }
        if let displayed = report.displayedKmh { payload["displayedKmh"] = displayed }
        if let source = report.displayedSource { payload["displayedSource"] = source.rawValue }
        if let deviceId { payload["deviceId"] = deviceId }
        let request = try client.request("POST", client.url("/api/speed-limits/reports"), json: payload, token: token, timeout: Self.timeout)
        let result = try await client.send(request)
        guard result.isSuccessful, let change = result.json?.object("change") else { return nil }
        return SpeedLimitChange(
            id: change.string("id"),
            status: .fromWire(change.string("status")),
            oldKmh: change.isNull("oldKmh") ? nil : change.int("oldKmh"),
            newKmh: change.isNull("newKmh") ? nil : change.int("newKmh"),
            reporters: change.int("reporters"),
            required: change.int("required")
        )
    }
}

/// Live driver positions (`/api/live`), for signed-in drivers.
public struct LiveAPI: Sendable {
    static let timeout: TimeInterval = 8

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    public func share(token: String, lat: Double, lon: Double, bearing: Double?, speedKmh: Int?, visible: Bool) async -> Bool {
        var payload: [String: Any] = ["lat": lat, "lon": lon, "visible": visible]
        if let bearing { payload["bearing"] = bearing }
        if let speedKmh { payload["speedKmh"] = speedKmh }
        guard let request = try? client.request("POST", client.url("/api/live/position"), json: payload, token: token, timeout: Self.timeout),
              let result = try? await client.send(request)
        else { return false }
        return result.isSuccessful
    }

    public func near(token: String, lat: Double, lon: Double, radiusM: Int) async -> [LiveUser] {
        let query = [URLQueryItem("lat", lat), URLQueryItem("lon", lon), URLQueryItem("radius", radiusM)]
        guard let result = try? await client.send(client.request("GET", client.url("/api/live/near", query: query), token: token, timeout: Self.timeout)),
              result.isSuccessful
        else { return [] }
        return (result.json?.objects("users") ?? []).map { o in
            LiveUser(
                id: o.string("id"),
                username: o.nonBlankString("username"),
                lat: o.double("lat"),
                lon: o.double("lon"),
                bearingDeg: o.isNull("bearing") ? nil : o.double("bearing"),
                avatarUrl: o.nonBlankString("avatarUrl")
            )
        }
    }
}
