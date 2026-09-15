import Foundation
import XRadarCore

/// Nearby crowdsourced data: point reports and aggregated radar-car zones.
public struct NearReports: Sendable, Hashable {
    public let reports: [UserReport]
    public let zones: [RadarZone]

    public init(reports: [UserReport] = [], zones: [RadarZone] = []) {
        self.reports = reports
        self.zones = zones
    }
}

/// A new report to post, with the extra fields some types require.
public struct NewReport: Sendable, Hashable {
    public let type: ReportType
    public let lat: Double
    public let lon: Double
    public let plate: String?
    public let street: String?
    public let side: String?
    /// "same" (my carriageway) or "opposite".
    public let direction: String
    /// The driver's course when reporting: orients the control zone.
    public let bearingDeg: Double?

    public init(
        type: ReportType,
        lat: Double,
        lon: Double,
        plate: String? = nil,
        street: String? = nil,
        side: String? = nil,
        direction: String = "same",
        bearingDeg: Double? = nil
    ) {
        self.type = type
        self.lat = lat
        self.lon = lon
        self.plate = plate
        self.street = street
        self.side = side
        self.direction = direction
        self.bearingDeg = bearingDeg
    }
}

/// Crowdsourced reports (`/api/reports`).
public struct ReportsAPI: Sendable {
    static let timeout: TimeInterval = 8

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    /// Nil when the backend did not answer properly: not "no reports", so the caller keeps its list.
    public func near(lat: Double, lon: Double, radiusM: Int, now: Date = Date()) async throws -> NearReports? {
        let url = try client.url("/api/reports/near", query: [URLQueryItem("lat", lat), URLQueryItem("lon", lon), URLQueryItem("radius", radiusM)])
        let result = try await client.send(client.request("GET", url, timeout: Self.timeout))
        guard result.isSuccessful, let json = result.json else { return nil }
        let nowMillis = Int(now.timeIntervalSince1970 * 1000)
        return NearReports(
            reports: (json.objects("reports") ?? []).compactMap { Self.report($0, nowMillis: nowMillis) },
            zones: (json.objects("zones") ?? []).compactMap(Self.zone)
        )
    }

    /// The report as the backend kept it (a new one, or the one it joined); nil when refused.
    /// Throws [AccessDenial] when the account may not report now (trial over, today's reports used).
    public func create(_ report: NewReport, token: String?, deviceId: String?, now: Date = Date()) async throws -> UserReport? {
        var payload: [String: Any] = [
            "type": report.type.rawValue,
            "lat": report.lat,
            "lon": report.lon,
            "direction": report.direction,
        ]
        if let deviceId { payload["deviceId"] = deviceId }
        if let plate = report.plate { payload["plate"] = plate }
        if let street = report.street { payload["street"] = street }
        if let side = report.side { payload["side"] = side }
        if let bearing = report.bearingDeg { payload["bearing"] = bearing }
        let request = try client.request("POST", client.url("/api/reports"), json: payload, token: token, timeout: Self.timeout)
        let result = try await client.send(request)
        if let denial = AccessDenial.of(result) { throw denial }
        guard result.isSuccessful else { return nil }
        return result.json?.object("report").flatMap { Self.report($0, nowMillis: Int(now.timeIntervalSince1970 * 1000)) }
    }

    public func delete(id: String, token: String?) async throws -> Bool {
        let url = try client.url("/api/reports/\(BackendClient.segment(id))")
        return try await client.send(client.request("DELETE", url, token: token, timeout: Self.timeout)).isSuccessful
    }

    /// "Toujours là" / "Plus là". Each person has one voice per report, so it goes with the account.
    public func vote(id: String, confirm: Bool, token: String?, deviceId: String?) async throws -> Bool {
        var payload: [String: Any] = [:]
        if let deviceId { payload["deviceId"] = deviceId }
        let url = try client.url("/api/reports/\(BackendClient.segment(id))/\(confirm ? "confirm" : "deny")")
        return try await client.send(client.request("POST", url, json: payload, token: token, timeout: Self.timeout)).isSuccessful
    }

    static func report(_ o: JSON, nowMillis: Int) -> UserReport? {
        guard let type = ReportType(rawValue: o.string("type")) else { return nil }
        return UserReport(
            id: o.string("id"),
            type: type,
            lat: o.double("lat"),
            lon: o.double("lon"),
            ageMillis: max(nowMillis - o.int("createdAt"), 0),
            confirmations: o.int("confirmations"),
            contradictions: o.int("contradictions"),
            reporters: max(o.int("reporters", 1), 1),
            direction: o.nonBlankString("direction") ?? "same",
            bearingDeg: o.isNull("bearing") ? nil : o.double("bearing"),
            score: o.int("score"),
            impactMeters: o.double("impactM", 1500),
            persistent: o.bool("persistent"),
            reporterRole: o.nonBlankString("reporterRole") ?? "guest",
            street: o.nonBlankString("street"),
            side: o.nonBlankString("side")
        )
    }

    static func zone(_ o: JSON) -> RadarZone? {
        guard let id = o.nonBlankString("id") else { return nil }
        return RadarZone(id: id, lat: o.double("lat"), lon: o.double("lon"), radiusMeters: o.double("radiusM"), count: o.int("count"))
    }
}
