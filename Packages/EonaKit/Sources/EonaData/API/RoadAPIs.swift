import Foundation
import EonaCore

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
    /// Nil when the request failed, so the caller keeps what it has and asks again.
    public func route(_ points: [GeoPoint]) async -> [RoadSign]? {
        guard points.count >= 2 else { return [] }
        guard let result = try? await client.send(client.request(
                  "POST", client.url("/api/signs/route"), json: ["coordinates": coordinates(points)], timeout: Self.timeout
              )),
              result.isSuccessful
        else { return nil }
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
    /// The faster-route check asks ORS and TomTom several times in a row.
    static let fasterTimeout: TimeInterval = 40

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    /// [avoid] holds "tolls", "highways" and/or "traffic". The backend refuses a restricted
    /// account, and a guest past today's trips, so the session [token] goes along: those
    /// refusals throw [AccessDenial]; nil is a route not obtained.
    public func route(from: GeoPoint, to: GeoPoint, avoid: [String] = [], token: String?) async throws -> Route? {
        var query = [URLQueryItem("from", "\(from.lat),\(from.lon)"), URLQueryItem("to", "\(to.lat),\(to.lon)")]
        if !avoid.isEmpty { query.append(URLQueryItem("avoid", avoid.joined(separator: ","))) }
        let result = try await client.send(client.request("GET", client.url("/api/route", query: query), token: token, timeout: Self.timeout))
        if let denial = AccessDenial.of(result) { throw denial }
        guard result.isSuccessful, let json = result.json else { return nil }
        return Self.route(json)
    }

    /// The rest of the route being followed ([remaining], from the driver) against variants
    /// around its traffic jams, all timed by TomTom with the traffic (`/api/route/faster`): a
    /// route only when the backend finds it saves enough time. [sinceRerouteSeconds], the time
    /// since the last switch for traffic, makes it stricter for a while. Nil otherwise, or when
    /// the check failed.
    public func faster(_ remaining: [GeoPoint], avoid: [String], sinceRerouteSeconds: Int?, token: String?) async -> FasterRoute? {
        guard remaining.count >= 2 else { return nil }
        var payload: [String: Any] = ["coordinates": coordinates(remaining), "avoid": avoid]
        if let sinceRerouteSeconds { payload["sinceRerouteS"] = sinceRerouteSeconds }
        guard let request = try? client.request("POST", client.url("/api/route/faster"), json: payload, token: token, timeout: Self.fasterTimeout),
              let result = try? await client.send(request),
              result.isSuccessful,
              let better = result.json?.object("better"),
              let routeJSON = better.object("route"),
              let route = Self.route(routeJSON)
        else { return nil }
        let gain = better.int("gainS")
        let closed = better.bool("closed")
        return gain > 0 || closed ? FasterRoute(route: route, gainSeconds: gain, closed: closed) : nil
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
        return Route(
            points: points,
            distanceMeters: json.int("distanceM"),
            durationSeconds: json.int("durationS"),
            steps: steps,
            engine: json.nonBlankString("engine"),
            mapVersion: json.nonBlankString("mapVersion")
        )
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

/// TomTom traffic on the route being followed (`/api/traffic/route`): the backend sends our route
/// to TomTom and answers with the slowed stretches on it, the TomTom key staying on the server.
public struct TrafficAPI: Sendable {
    static let timeout: TimeInterval = 15
    static let probeTimeout: TimeInterval = 10

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    /// Nil when the backend could not say (no TomTom key, TomTom silent, offline): the caller
    /// keeps what it shows. An empty answer is a clear road. [aheadMeters], the driver's metres
    /// along [points], lets the backend say whether a faster route is worth looking for.
    public func route(_ points: [GeoPoint], aheadMeters: Double? = nil, token: String?) async -> RouteTraffic? {
        var payload: [String: Any] = ["coordinates": coordinates(points)]
        if let aheadMeters { payload["aheadM"] = aheadMeters.rounded() }
        guard points.count >= 2,
              let request = try? client.request("POST", client.url("/api/traffic/route"), json: payload, token: token, timeout: Self.timeout),
              let result = try? await client.send(request),
              result.isSuccessful,
              let json = result.json
        else { return nil }
        return Self.traffic(json)
    }

    /// "Partager les ralentissements": a slowdown the app measured, sent without the account being
    /// kept with it. True when the jam is already known there (the driver is asked nothing),
    /// false when not; nil when the backend refused it or could not say.
    public func probe(_ slowdown: Slowdown, token: String?) async -> Bool? {
        let payload: [String: Any] = [
            "lat": slowdown.lat, "lon": slowdown.lon, "bearing": slowdown.bearingDeg,
            "speedKmh": slowdown.speedKmh, "limitKmh": slowdown.limitKmh,
        ]
        guard let request = try? client.request("POST", client.url("/api/traffic/probe"), json: payload, token: token, timeout: Self.probeTimeout),
              let result = try? await client.send(request),
              result.isSuccessful,
              let json = result.json
        else { return nil }
        return json.bool("known")
    }

    /// "Non" to "Ralentissement du trafic ?": the driver's recent probes are taken back.
    public func dismissProbe(token: String?) async {
        guard let request = try? client.request("POST", client.url("/api/traffic/probe/dismiss"), json: [:], token: token, timeout: Self.probeTimeout) else { return }
        _ = try? await client.send(request)
    }

    static func traffic(_ json: JSON) -> RouteTraffic {
        RouteTraffic(
            totalMeters: json.double("totalM"),
            stretches: (json.objects("sections") ?? []).compactMap { o in
                guard let level = TrafficLevel(rawValue: o.string("level")) else { return nil }
                let from = o.double("fromM")
                let to = o.double("toM")
                let delay = o.has("delayS") && !o.isNull("delayS") ? o.int("delayS") : nil
                // A section without a source (an older backend, or TomTom's own) is TomTom's.
                let source = o.nonBlankString("source") ?? TrafficStretch.tomtom
                return to > from ? TrafficStretch(fromMeters: from, toMeters: to, level: level, delaySeconds: delay, source: source) : nil
            },
            worthChecking: json.bool("check")
        )
    }
}

/// Presence (`/api/live`): the app says it is open, and whether a trip runs. Counted by the
/// backend, shown to nobody, and no position goes with it.
public struct LiveAPI: Sendable {
    static let timeout: TimeInterval = 8

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    /// What goes with the ping follows the privacy switches: a position only with "Présence et
    /// position", the time spent only with "Temps d'utilisation". Nothing else is ever sent.
    public func presence(
        token: String,
        inTrip: Bool,
        position: GeoPoint? = nil,
        speedKmh: Int? = nil,
        countTime: Bool = false
    ) async -> Bool {
        var json: [String: Any] = ["inTrip": inTrip]
        if countTime { json["session"] = true }
        if let position {
            json["lat"] = position.lat
            json["lon"] = position.lon
            if let speedKmh { json["speedKmh"] = speedKmh }
        }
        guard let request = try? client.request("POST", client.url("/api/live/presence"), json: json, token: token, timeout: Self.timeout),
              let result = try? await client.send(request)
        else { return false }
        return result.isSuccessful
    }
}
