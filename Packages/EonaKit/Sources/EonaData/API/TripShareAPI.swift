import Foundation
import EonaCore

/// The link a driver hands out, as their own app sees it.
public struct TripShare: Sendable, Hashable {
    public let token: String
    public let url: URL
    public let endsAt: Date
    public let followers: Int
    public let arrived: Bool
}

/// A trip being followed, as the other person's app sees it: where the driver is, where they go,
/// and when they should get there. Nothing else travels.
public struct FollowedTrip: Sendable, Hashable {
    public let name: String
    public let toLabel: String?
    public let destination: GeoPoint?
    public let route: [GeoPoint]
    public let position: GeoPoint?
    public let bearing: Double?
    public let remainingMeters: Int?
    public let etaAt: Date?
    public let arrived: Bool
}

/// "Partager mon trajet" (`/api/trips`): the driver opens a link, someone follows the trip live,
/// and everything stops at the arrival. The backend keeps it in memory — no trace is written.
public struct TripShareAPI: Sendable {
    static let timeout: TimeInterval = 8

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    /// Opens the link for the trip being driven; nil when the backend refuses.
    public func open(toLabel: String?, destination: GeoPoint?, route: [GeoPoint], token: String?) async -> TripShare? {
        var json: [String: Any] = [:]
        if let toLabel { json["toLabel"] = toLabel }
        if let destination { json["destination"] = ["lat": destination.lat, "lon": destination.lon] }
        if !route.isEmpty { json["route"] = route.map { [$0.lon, $0.lat] } }
        return await share("POST", json: json, token: token)
    }

    /// Where the driver is now, and what is left of the trip.
    @discardableResult
    public func update(
        position: GeoPoint?,
        bearing: Double?,
        remainingMeters: Int?,
        etaSeconds: Int?,
        arrived: Bool = false,
        token: String?
    ) async -> TripShare? {
        var json: [String: Any] = [:]
        if let position {
            json["lat"] = position.lat
            json["lon"] = position.lon
        }
        if let bearing { json["bearing"] = bearing }
        if let remainingMeters { json["remainingM"] = remainingMeters }
        if let etaSeconds { json["etaS"] = etaSeconds }
        if arrived { json["arrived"] = true }
        return await share("PATCH", json: json, token: token)
    }

    /// The driver's own live link, when the app comes back and one is still running.
    public func mine(token: String?) async -> TripShare? {
        await share("GET", json: nil, token: token)
    }

    /// Stops sharing: the link stops working at once.
    @discardableResult
    public func close(token: String?) async -> Bool {
        guard let request = try? client.request("DELETE", client.url("/api/trips/share"), token: token, timeout: Self.timeout),
              let result = try? await client.send(request)
        else { return false }
        return result.isSuccessful
    }

    /// The trip behind a shared link; nil once it is over.
    public func follow(_ shareToken: String, token: String?) async -> FollowedTrip? {
        guard let request = try? client.request(
                  "GET",
                  client.url("/api/trips/shared/\(BackendClient.segment(shareToken))"),
                  token: token,
                  timeout: Self.timeout
              ),
              let result = try? await client.send(request), result.isSuccessful,
              let share = result.json?.object("share")
        else { return nil }
        return Self.followed(share)
    }

    private func share(_ method: String, json: [String: Any]?, token: String?) async -> TripShare? {
        guard let request = try? client.request(method, client.url("/api/trips/share"), json: json, token: token, timeout: Self.timeout),
              let result = try? await client.send(request), result.isSuccessful,
              let share = result.json?.object("share"),
              let url = URL(string: share.string("url"))
        else { return nil }
        let token = share.string("token")
        guard !token.isEmpty else { return nil }
        return TripShare(
            token: token,
            url: url,
            endsAt: Self.date(share.nonBlankString("endsAt")) ?? Date().addingTimeInterval(3600),
            followers: share.int("followers"),
            arrived: share.bool("arrived")
        )
    }

    private static func followed(_ share: JSON) -> FollowedTrip {
        let position = share.object("position")
        let bearing = position?.double("bearing")
        return FollowedTrip(
            name: share.nonBlankString("name") ?? "Un conducteur",
            toLabel: share.nonBlankString("toLabel"),
            destination: point(share.object("destination")),
            route: (share.array("route") ?? []).compactMap(JSON.lonLat),
            position: point(position),
            bearing: (bearing?.isFinite ?? false) ? bearing : nil,
            remainingMeters: share.isNull("remainingM") ? nil : share.int("remainingM"),
            etaAt: Self.date(share.nonBlankString("etaAt")),
            arrived: share.bool("arrived")
        )
    }

    private static func point(_ value: JSON?) -> GeoPoint? {
        guard let value else { return nil }
        let lat = value.double("lat")
        let lon = value.double("lon")
        return lat.isFinite && lon.isFinite ? GeoPoint(lat: lat, lon: lon) : nil
    }

    /// The backend writes fractional seconds; the plain reader would refuse them.
    private static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return withFraction.date(from: text) ?? plain.date(from: text)
    }

    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain = ISO8601DateFormatter()
}
