import Foundation

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

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    /// The account (from [token]) is the author: nothing else about the driver goes.
    public func send(category: BugCategory, description: String, steps: String?, app: BugAppDetails, token: String?) async -> BugSendOutcome {
        var payload: [String: Any] = [
            "category": category.rawValue,
            "description": description,
            "app": ["platform": app.platform, "version": app.version, "os": app.os, "model": app.model],
        ]
        if let steps, !steps.isEmpty { payload["steps"] = steps }
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
