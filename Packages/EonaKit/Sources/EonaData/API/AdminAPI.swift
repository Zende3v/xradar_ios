import Foundation

/// Pilotage : session administrateur obligatoire, aucun repli sur identifiant appareil.
public struct AdminAPI: Sendable {
    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) { self.client = client }

    public func overview(token: String) async throws -> AdminOverview {
        try await call("GET", "/api/admin/overview", token: token)
    }

    public func trips(offset: Int = 0, token: String) async throws -> AdminTripsPage {
        try await call("GET", "/api/admin/trips", query: [URLQueryItem("limit", 40), URLQueryItem("offset", offset)], token: token)
    }

    public func accounts(query: String = "", role: String? = nil, banned: Bool? = nil, offset: Int = 0, token: String) async throws -> AdminAccountsPage {
        var items = [URLQueryItem("limit", 50), URLQueryItem("offset", offset)]
        if !query.isEmpty { items.append(URLQueryItem("q", query)) }
        if let role { items.append(URLQueryItem("role", role)) }
        if let banned { items.append(URLQueryItem("banned", banned ? "true" : "false")) }
        return try await call("GET", "/api/admin/accounts", query: items, token: token)
    }

    public func account(id: String, token: String) async throws -> AdminAccount {
        let envelope: AccountEnvelope = try await call("GET", path(id), token: token)
        return envelope.account
    }

    public func action(id: String, action: String, reason: String? = nil, token: String) async throws -> AdminActionResult {
        var payload: [String: Any] = ["action": action]
        if let reason, !reason.isEmpty { payload["reason"] = reason }
        return try await call("POST", path(id) + "/action", json: payload, token: token)
    }

    public func bans(token: String) async throws -> AdminBansPage {
        try await call("GET", "/api/admin/accounts/bans", token: token)
    }

    public func update(id: String, role: String, displayName: String, token: String) async throws -> AdminAccount {
        let envelope: AccountEnvelope = try await call("PATCH", path(id), json: ["role": role, "displayName": displayName], token: token)
        return envelope.account
    }

    public func create(username: String, email: String, password: String, role: String, token: String) async throws -> AdminAccount {
        let envelope: AccountEnvelope = try await call("POST", "/api/admin/accounts", json: ["username": username, "email": email, "password": password, "role": role], token: token)
        return envelope.account
    }

    private func path(_ id: String) -> String { "/api/admin/accounts/" + BackendClient.segment(id) }

    private func call<Value: Decodable & Sendable>(_ method: String, _ path: String, query: [URLQueryItem] = [], json: [String: Any]? = nil, token: String) async throws -> Value {
        guard !token.isEmpty else { throw AdminAPIError.unauthorized }
        try Task.checkCancellation()
        let request = try client.request(method, client.url(path, query: query), json: json, token: token, timeout: 15)
        let result = try await client.send(request)
        try Task.checkCancellation()
        if result.status == 401 { throw AdminAPIError.unauthorized }
        if result.status == 403 { throw AdminAPIError.forbidden }
        if result.status >= 500 { throw AdminAPIError.unavailable }
        guard result.isSuccessful else {
            throw AdminAPIError.refused(result.json?.nonBlankString("error") ?? "request failed")
        }
        do { return try JSONDecoder().decode(Value.self, from: result.data) }
        catch { throw AdminAPIError.invalidResponse }
    }

    private struct AccountEnvelope: Decodable, Sendable { let account: AdminAccount }
}

public enum AdminAPIError: Error, Sendable, LocalizedError {
    case unauthorized, forbidden, unavailable, invalidResponse, refused(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "Session expirée. Reconnecte-toi."
        case .forbidden: "Accès administrateur retiré."
        case .unavailable: "Service indisponible. Réessaie."
        case .invalidResponse: "Réponse serveur indisponible. Réessaie."
        case .refused(let message):
            switch message {
            case "cannot demote or ban yourself", "cannot moderate yourself", "cannot demote, ban or suspend yourself", "cannot ban your own identity": "Impossible de modifier tes propres droits ici."
            case "cannot disable last admin", "cannot delete last admin": "Dernier admin actif : modification interdite."
            case "member identity required": "Email, pseudo et authentification requis avant changement de rôle."
            case "not found": "Compte introuvable."
            case "email already registered": "Email déjà utilisé."
            case "username taken": "Pseudo déjà utilisé."
            case "invalid role": "Rôle invalide."
            default: "Action refusée. Vérifie les champs et réessaie."
            }
        }
    }
}

public struct AdminOverview: Decodable, Sendable {
    public let generatedAt: String
    public let presence: AdminPresence
    public let accounts: AdminAccountCounts
    public let trips: AdminTripCounts
    public let routing: AdminRouting
    public let routingStats: AdminRoutingStats
    public let here: AdminHereUsage
}

public struct AdminPresence: Decodable, Sendable {
    public let ttlSeconds: Int
    public let groups: [AdminPresenceGroup]
    public let online: Int
    public let offline: Int
    public let inTrip: Int
}

public struct AdminPresenceGroup: Decodable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let total: Int
    public let online: Int
    public let offline: Int
    public let inTrip: Int
}

public struct AdminAccountCounts: Decodable, Sendable {
    public let total: Int
    public let banned: Int
    public let suspended: Int
}

public struct AdminTripCounts: Decodable, Sendable {
    public let retainedCount: Int
    public let totalRecorded: Int
}

public struct AdminRouting: Decodable, Sendable {
    public let provider: String?
    public let mode: String?
    public let valhalla: AdminValhalla
    public let fallbacks: AdminFallbacks?
}

public struct AdminValhalla: Decodable, Sendable {
    public let state: String
    public let version: String?
    public let mapVersion: String?
    public let hasLiveTraffic: Bool?
    public let statusAt: String?
}

public struct AdminFallbacks: Decodable, Sendable {
    public let total: Int?
    public let since: String?
}

public struct AdminRoutingStats: Decodable, Sendable {
    public let available: Bool
    public let retentionDays: Int
    public let totalRequests: Int?
    public let totalErrors: Int?
    public let cacheHits: Int?
    public let weekRequests: Int?
    public let weekErrors: Int?
    public let medianMs: Double?
    public let p95Ms: Double?
}

public struct AdminHereUsage: Decodable, Sendable {
    public let monthUsed: Int
    public let dailyCap: Int?
    public let monthlyBudgetEUR: Double?
    public let estimatedMonthEUR: Double?
    public let blocked: String?
    public let estimateOnly: Bool
    public let history: AdminHereHistory
}

public struct AdminHereHistory: Decodable, Sendable {
    public let since: String
    public let baselineMonth: String?
    public let totalRequests: Int
    public let totalEstimatedEUR: Double?
    public let weekStart: String
    public let weekRequests: Int
    public let weekEstimatedEUR: Double?
    public let weekComplete: Bool
    public let earlierHistoryComplete: Bool
}

public struct AdminTripsPage: Decodable, Sendable {
    public let total: Int
    public let count: Int
    public let offset: Int
    public let next: Int?
    public let retentionPerAccount: Int
    public let trips: [AdminTrip]
}

/// Flux anonyme : aucun nom, identifiant compte ni lieu.
public struct AdminTrip: Decodable, Sendable, Identifiable {
    public let id: String
    public let startedAt: Double
    public let distanceMeters: Int
    public let durationSeconds: Int
    public let arrived: Bool?
    public let engines: [String]
    public let platform: String?
}

public struct AdminAccountsPage: Decodable, Sendable {
    public let total: Int
    public let next: Int?
    public let accounts: [AdminAccount]
}

public struct AdminAccount: Decodable, Sendable, Identifiable {
    public let id: String
    public let username: String?
    public let displayName: String?
    public let email: String?
    public let role: String
    public let access: String?
    public let tier: String?
    public let hasPlus: Bool?
    public let banned: Bool
    public let banId: String?
    public let banReason: String?
    public let bannedAt: String?
    public let suspended: Bool?
    public let revoked: Bool?
    public let createdAt: String?
    public let lastSeenAt: String?
    public let platform: String?
    public let app: AdminAppInfo?
    public let stats: AdminAccountStats?
    public let online: Bool?
    public let inTrip: Bool?
    public let knownDeviceIds: [String]?
    public let deviceIds: [String]?
    public let deviceId: String?

    public var name: String {
        [displayName, username].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "Compte"
    }
    public var devices: [String] {
        var values = knownDeviceIds ?? deviceIds ?? []
        if let deviceId, !deviceId.isEmpty, !values.contains(deviceId) { values.append(deviceId) }
        return values.filter { !$0.isEmpty }
    }
}

public struct AdminAppInfo: Decodable, Sendable {
    public let model: String?
    public let osVersion: String?
    public let appVersion: String?
}

public struct AdminAccountStats: Decodable, Sendable {
    public let tripCount: Int?
    public let distanceMeters: Int?
    public let driveDurationSeconds: Int?
}

public struct AdminActionResult: Decodable, Sendable {
    public let account: AdminAccount?
    public let revokedSessions: Int?
    public let unbanned: Bool?
}

public struct AdminBansPage: Decodable, Sendable {
    public let total: Int
    public let bans: [AdminBanRecord]
}

public struct AdminBanRecord: Decodable, Sendable, Identifiable {
    public let accountId: String
    public let accountExists: Bool
    public let displayName: String?
    public let email: String?
    public let bannedAt: String?
    public let reason: String?
    public let deviceCount: Int
    public var id: String { accountId }
}
