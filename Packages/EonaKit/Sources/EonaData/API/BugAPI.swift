import Foundation
import EonaCore

/// "Signaler un bug": where the problem is.
public enum BugCategory: String, Sendable, Hashable, CaseIterable {
    case map
    case navigation
    case alerts
    case account
    case other

    public var label: String {
        switch self {
        case .map: "Carte"
        case .navigation: "Navigation"
        case .alerts: "Alertes"
        case .account: "Compte"
        case .other: "Autre"
        }
    }
}

/// Where a bug report stands, for the developers: Nouveau → En cours → Résolu.
public enum BugStatus: String, Sendable, Hashable, CaseIterable {
    case new
    case progress
    case resolved

    public var label: String {
        switch self {
        case .new: "Nouveau"
        case .progress: "En cours"
        case .resolved: "Résolu"
        }
    }
}

/// What the app knows of itself, sent with a report (nothing the driver types).
public struct BugAppDetails: Sendable, Hashable {
    public let platform: String
    public let version: String
    public let os: String
    public let model: String

    public init(platform: String, version: String, os: String, model: String) {
        self.platform = platform
        self.version = version
        self.os = os
        self.model = model
    }
}

/// The trip a navigation report comes with (D7.4): the one being driven ([inProgress]), else the
/// last one finished since the app started. Times in epoch millis; [route] is the one followed.
public struct BugTripContext: Sendable, Hashable {
    public let inProgress: Bool
    public let toLabel: String?
    public let startedAt: Int?
    public let departedAt: Int?
    /// Driven so far, or in all once over.
    public let distanceMeters: Int?
    public let plannedMeters: Int?
    public let destination: GeoPoint?
    public let route: [GeoPoint]?

    public init(
        inProgress: Bool,
        toLabel: String?,
        startedAt: Int?,
        departedAt: Int?,
        distanceMeters: Int?,
        plannedMeters: Int?,
        destination: GeoPoint?,
        route: [GeoPoint]?
    ) {
        self.inProgress = inProgress
        self.toLabel = toLabel
        self.startedAt = startedAt
        self.departedAt = departedAt
        self.distanceMeters = distanceMeters
        self.plannedMeters = plannedMeters
        self.destination = destination
        self.route = route
    }
}

/// What the app joins to a navigation report on its own (D7.4): the engine and the map of the
/// route, and the trip. All nil when no trip was driven since the app started.
public struct BugContext: Sendable, Hashable {
    public static let empty = BugContext(engine: nil, mapVersion: nil, trip: nil)

    public let engine: String?
    public let mapVersion: String?
    public let trip: BugTripContext?

    public init(engine: String?, mapVersion: String?, trip: BugTripContext?) {
        self.engine = engine
        self.mapVersion = mapVersion
        self.trip = trip
    }
}

/// A report as the developers see it.
public struct BugReport: Sendable, Hashable, Identifiable {
    public let id: String
    public let status: BugStatus
    public let category: BugCategory
    public let description: String
    public let steps: String?
    public let createdAt: String
    /// The author's pseudo and role; nil once the account is deleted.
    public let author: String?
    public let app: BugAppDetails

    public init(id: String, status: BugStatus, category: BugCategory, description: String, steps: String?, createdAt: String, author: String?, app: BugAppDetails) {
        self.id = id
        self.status = status
        self.category = category
        self.description = description
        self.steps = steps
        self.createdAt = createdAt
        self.author = author
        self.app = app
    }
}

/// How sending a report went.
public enum BugSendOutcome: Sendable, Hashable {
    case sent
    /// Too many reports lately: later.
    case tooMany
    case failed
}

/// Bug reports (`/api/bugs`): anyone sends, admins read and set the status.
public struct BugAPI: Sendable {
    static let timeout: TimeInterval = 10
    /// The route joined to a navigation report: this many points at most.
    static let maxRoutePoints = 600

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    /// The account (from [token]) is the author: nothing else about the driver goes, except the
    /// trip [context] of a navigation report (any other category leaves it out).
    public func send(
        category: BugCategory,
        description: String,
        steps: String?,
        app: BugAppDetails,
        context: BugContext? = nil,
        token: String?
    ) async -> BugSendOutcome {
        var payload: [String: Any] = [
            "category": category.rawValue,
            "description": description,
            "app": ["platform": app.platform, "version": app.version, "os": app.os, "model": app.model],
        ]
        if let steps, !steps.isEmpty { payload["steps"] = steps }
        if category == .navigation, let context { payload["context"] = Self.wireContext(context) }
        guard let request = try? client.request("POST", client.url("/api/bugs"), json: payload, token: token, timeout: Self.timeout),
              let result = try? await client.send(request)
        else { return .failed }
        if result.status == 429 { return .tooMany }
        return result.isSuccessful ? .sent : .failed
    }

    /// The most recent reports ([status] nil: all), older than [before] (ISO); nil when refused or offline.
    public func list(status: BugStatus?, before: String? = nil, token: String?) async -> [BugReport]? {
        var query: [URLQueryItem] = []
        if let status { query.append(URLQueryItem(name: "status", value: status.rawValue)) }
        if let before { query.append(URLQueryItem(name: "before", value: before)) }
        guard let request = try? client.request("GET", client.url("/api/bugs", query: query), token: token, timeout: Self.timeout),
              let result = try? await client.send(request),
              result.isSuccessful,
              let json = result.json
        else { return nil }
        return (json.objects("reports") ?? []).compactMap(Self.report)
    }

    public func setStatus(_ status: BugStatus, of id: String, token: String?) async -> Bool {
        guard let request = try? client.request(
                  "PATCH", client.url("/api/bugs/\(BackendClient.segment(id))"), json: ["status": status.rawValue], token: token, timeout: Self.timeout
              ),
              let result = try? await client.send(request)
        else { return false }
        return result.isSuccessful
    }

    /// The context as the backend reads it: an unknown value as JSON null, the destination as
    /// `{lat, lon}`, the route as `[[longitude, latitude], …]` made light enough to send.
    static func wireContext(_ context: BugContext) -> [String: Any] {
        var trip: Any = NSNull()
        if let t = context.trip {
            let route = t.route.flatMap { points -> [[Double]]? in
                points.isEmpty ? nil : coordinates(LineSimplifier.simplify(points, maxPoints: Self.maxRoutePoints))
            }
            trip = [
                "inProgress": t.inProgress,
                "toLabel": orNull(t.toLabel),
                "startedAt": orNull(t.startedAt),
                "departedAt": orNull(t.departedAt),
                "distanceMeters": orNull(t.distanceMeters),
                "plannedMeters": orNull(t.plannedMeters),
                "destination": orNull(t.destination.map { ["lat": $0.lat, "lon": $0.lon] }),
                "route": orNull(route),
            ] as [String: Any]
        }
        return [
            "engine": orNull(context.engine),
            "mapVersion": orNull(context.mapVersion),
            "trip": trip,
        ]
    }

    static func report(_ o: JSON) -> BugReport? {
        guard let status = BugStatus(rawValue: o.string("status")), !o.string("id").isEmpty else { return nil }
        let author = o.object("author").map { a in
            let role = a.string("role")
            return (a.nonBlankString("username") ?? "Sans pseudo") + (role.isEmpty ? "" : " · \(role)")
        }
        let app = o.object("app")
        return BugReport(
            id: o.string("id"),
            status: status,
            category: BugCategory(rawValue: o.string("category")) ?? .other,
            description: o.string("description"),
            steps: o.nonBlankString("steps"),
            createdAt: o.string("createdAt"),
            author: author,
            app: BugAppDetails(
                platform: app?.string("platform") ?? "",
                version: app?.string("version") ?? "",
                os: app?.string("os") ?? "",
                model: app?.string("model") ?? ""
            )
        )
    }
}
