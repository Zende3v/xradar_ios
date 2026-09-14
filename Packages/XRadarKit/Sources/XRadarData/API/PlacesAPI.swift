import Foundation
import XRadarCore

/// Nearest fuel stations, chargers, car parks… from the backend (`/api/places`, PostGIS).
public struct PlacesAPI: Sendable {
    /// The backend answers from its own database in milliseconds.
    static let timeout: TimeInterval = 10

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    /// The pool of nearest places of [category] (up to 60), for [NearbyPicker] to rank; nil when
    /// the search failed (no network, backend down).
    public func near(category: PlaceCategory, lat: Double, lon: Double) async -> [Place]? {
        let query = [URLQueryItem("lat", lat), URLQueryItem("lon", lon), URLQueryItem("kind", category.rawValue), URLQueryItem("pool", 1)]
        guard let result = try? await client.send(client.request("GET", client.url("/api/places/near", query: query), timeout: Self.timeout)),
              result.isSuccessful,
              let json = result.json
        else { return nil }
        return Self.places(json, category: category)
    }

    static func places(_ json: JSON, category: PlaceCategory) -> [Place] {
        (json.objects("places") ?? []).compactMap { o in
            guard let name = o.nonBlankString("name") else { return nil }
            let stars = o.isNull("stars") ? nil : o.int("stars")
            let nearby = NearbyInfo(
                brand: o.nonBlankString("brand"),
                hours: o.object("hours").map(hours),
                customersOnly: o.bool("customersOnly"),
                charging: o.object("charging").map(charging),
                parking: o.object("parking").map(parking),
                stars: stars.flatMap { (1...5).contains($0) ? $0 : nil }
            )
            return Place(
                id: o.nonBlankString("id") ?? "\(o.double("lat")),\(o.double("lon"))",
                name: name,
                subtitle: o.nonBlankString("subtitle") ?? "",
                kind: .result,
                lat: o.double("lat"),
                lon: o.double("lon"),
                // Official prices exist for fuel stations only.
                fuel: category == .fuel ? o.object("fuel").flatMap(fuel) : nil,
                distanceMeters: o.has("distanceM") ? o.int("distanceM") : nil,
                nearby: nearby
            )
        }
    }

    /// `{state, alwaysOpen, today: [{from, to}], nextAt, source}`.
    static func hours(_ o: JSON) -> OpeningHours {
        let state: OpenState
        switch o.string("state") {
        case "open": state = .open
        case "closed": state = .closed
        default: state = .unknown
        }
        let today = (o.objects("today") ?? []).compactMap { slot -> TimeSlot? in
            guard let from = slot.nonBlankString("from"), let to = slot.nonBlankString("to") else { return nil }
            return TimeSlot(from: from, to: to)
        }
        return OpeningHours(
            state: state,
            alwaysOpen: o.bool("alwaysOpen"),
            today: today,
            nextChangeMillis: o.isNull("nextAt") ? nil : o.int("nextAt"),
            official: o.string("source") == "official"
        )
    }

    /// `{maxKw, connectors: [...], points}`.
    static func charging(_ o: JSON) -> ChargingInfo {
        let maxKw = o.isNull("maxKw") ? nil : o.double("maxKw")
        let points = o.isNull("points") ? nil : o.int("points")
        return ChargingInfo(
            maxKw: maxKw.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
            connectors: o.strings("connectors"),
            points: points.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    /// `{fee, type, capacity, parkAndRide}`.
    static func parking(_ o: JSON) -> ParkingInfo {
        let type: ParkingType?
        switch o.nonBlankString("type") {
        case "underground"?: type = .underground
        case "multi_storey"?: type = .multiStorey
        case "rooftop"?: type = .rooftop
        case "surface"?: type = .surface
        case "street_side"?: type = .streetSide
        default: type = nil
        }
        let capacity = o.isNull("capacity") ? nil : o.int("capacity")
        return ParkingInfo(
            fee: o.isNull("fee") ? nil : o.bool("fee"),
            type: type,
            capacity: capacity.flatMap { $0 > 0 ? $0 : nil },
            parkAndRide: o.bool("parkAndRide")
        )
    }

    /// `{stationId, matchedBy, prices: [{fuel, price, updatedAt, outOfStock}]}`.
    static func fuel(_ o: JSON) -> StationFuel? {
        guard let stationId = o.nonBlankString("stationId") else { return nil }
        let prices = (o.objects("prices") ?? []).compactMap { p -> FuelPrice? in
            guard let type = FuelType(rawValue: p.string("fuel")) else { return nil }
            let euros = p.double("price")
            guard euros.isFinite, euros > 0 else { return nil }
            return FuelPrice(type: type, euros: euros, updatedAt: p.nonBlankString("updatedAt"), outOfStock: p.bool("outOfStock"))
        }
        return StationFuel(stationId: stationId, matchedBy: o.string("matchedBy"), prices: prices)
    }
}

/// French address search: Base Adresse Nationale (api-adresse.data.gouv.fr), official, no key.
public struct GeocodingAPI: Sendable {
    static let endpoint = "https://api-adresse.data.gouv.fr/search/"
    static let timeout: TimeInterval = 8

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// [aroundLat]/[aroundLon] bias the results toward the driver, so "rue de la gare" returns
    /// the one next to them and not the other end of France.
    public func search(_ query: String, limit: Int = 8, aroundLat: Double? = nil, aroundLon: Double? = nil) async throws -> [Place] {
        var items = [URLQueryItem("q", query), URLQueryItem("limit", limit)]
        if let aroundLat, let aroundLon {
            items += [URLQueryItem("lat", aroundLat), URLQueryItem("lon", aroundLon)]
        }
        let url = try BackendClient.url(Self.endpoint, query: items)
        let request = URLRequest(url: url, timeoutInterval: Self.timeout)
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode), let json = JSON(data: data) else { return [] }
        return (json.objects("features") ?? []).compactMap { feature in
            guard let point = JSON.lonLat(feature.object("geometry")?.raw["coordinates"]) else { return nil }
            let properties = feature.object("properties") ?? JSON([:])
            let label = properties.string("label").isEmpty ? properties.string("name") : properties.string("label")
            guard !label.isEmpty else { return nil }
            let id = properties.string("id")
            return Place(
                id: id.isEmpty ? "\(point.lat),\(point.lon)" : id,
                name: label,
                subtitle: properties.string("context"),
                kind: .result,
                lat: point.lat,
                lon: point.lon
            )
        }
    }
}

/// One line of the in-app diagnostic screen.
public struct CheckResult: Sendable, Hashable {
    public let name: String
    public let ok: Bool
    public let detail: String

    public init(name: String, ok: Bool, detail: String) {
        self.name = name
        self.ok = ok
        self.detail = detail
    }
}

/// Live connectivity check against the backend, for the in-app diagnostic screen.
public struct BackendDiagnostics: Sendable {
    static let timeout: TimeInterval = 6

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    public var baseURL: URL {
        client.baseURL
    }

    public func run() async -> [CheckResult] {
        let health = await check("Santé du serveur (/health)", "/health")
        let radars = await check(
            "Radars (/near, Montpellier)",
            "/api/radars/near",
            query: [URLQueryItem("lat", 43.6126), URLQueryItem("lon", 3.8767), URLQueryItem("radius", 5000)]
        )
        return [health, radars]
    }

    private func check(_ name: String, _ path: String, query: [URLQueryItem] = []) async -> CheckResult {
        do {
            let result = try await client.send(client.request("GET", client.url(path, query: query), timeout: Self.timeout))
            return CheckResult(name: name, ok: result.isSuccessful, detail: "HTTP \(result.status)\n\(result.text.prefix(220))")
        } catch {
            return CheckResult(name: name, ok: false, detail: "Échec : \(type(of: error))\n\(error.localizedDescription)")
        }
    }
}
