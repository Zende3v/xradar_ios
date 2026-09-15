import Foundation
import XRadarCore

/// An account plus its session token (nil token when unauthenticated).
public struct AuthResult: Sendable, Hashable {
    public let account: Account
    public let token: String?

    public init(account: Account, token: String?) {
        self.account = account
        self.token = token
    }
}

/// Server-side statistics of the signed-in account.
public struct AccountStats: Sendable, Hashable {
    public let tripCount: Int
    public let distanceMeters: Int
    public let driveSeconds: Int
    public let alertsTraversed: Int
    public let reportsDeclared: Int
    public let reportsConfirmed: Int
    public let trust: Double
    public let trips: [TripRecord]

    public init(
        tripCount: Int = 0,
        distanceMeters: Int = 0,
        driveSeconds: Int = 0,
        alertsTraversed: Int = 0,
        reportsDeclared: Int = 0,
        reportsConfirmed: Int = 0,
        trust: Double = 2.5,
        trips: [TripRecord] = []
    ) {
        self.tripCount = tripCount
        self.distanceMeters = distanceMeters
        self.driveSeconds = driveSeconds
        self.alertsTraversed = alertsTraversed
        self.reportsDeclared = reportsDeclared
        self.reportsConfirmed = reportsConfirmed
        self.trust = trust
        self.trips = trips
    }
}

/// A referral code an admin minted, and how many accounts used it.
public struct ReferralCode: Sendable, Hashable {
    public let code: String
    public let createdAt: String
    public let months: Int
    public let redemptions: Int

    public init(code: String, createdAt: String, months: Int, redemptions: Int) {
        self.code = code
        self.createdAt = createdAt
        self.months = months
        self.redemptions = redemptions
    }
}

/// Result of an auth call: success, or a message the driver can read.
public enum AuthOutcome: Sendable, Hashable {
    case success(AuthResult)
    case failure(String)
}

/// Accounts, auth, sessions and profile (`/api/accounts`).
public struct AccountAPI: Sendable {
    /// Sent with device sign-ins so the backend knows which app signs in.
    static let platform = "ios"
    static let timeout: TimeInterval = 10

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    public func usernameAvailable(_ username: String) async throws -> Bool {
        let result = try await client.send(request("GET", "/api/accounts/username-available", query: [URLQueryItem("u", username)]))
        return result.json?.bool("available") ?? false
    }

    /// Device sign-in, restoring the session bound to this phone; nil when it fails.
    public func authDevice(deviceId: String) async -> AuthResult? {
        guard let result = try? await client.send(request("POST", "/api/accounts/auth", json: ["deviceId": deviceId, "platform": Self.platform])),
              result.isSuccessful
        else { return nil }
        return Self.auth(result.json)
    }

    public func claimGuest(deviceId: String, username: String, password: String) async -> AuthOutcome {
        await outcome {
            try request("POST", "/api/accounts/guest", json: [
                "deviceId": deviceId, "username": username, "password": password, "platform": Self.platform,
            ])
        }
    }

    public func register(email: String, password: String, username: String, referralCode: String?) async -> AuthOutcome {
        var payload: [String: Any] = ["email": email, "password": password, "username": username]
        if let code = referralCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            payload["referralCode"] = code
        }
        return await outcome { try request("POST", "/api/accounts/register", json: payload) }
    }

    /// [identifier]: an email (member) or a username (guest); [deviceId] attaches the account to this phone.
    public func login(identifier: String, password: String, deviceId: String?) async -> AuthOutcome {
        var payload: [String: Any] = ["identifier": identifier, "password": password]
        if let deviceId, !deviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["deviceId"] = deviceId
        }
        return await outcome { try request("POST", "/api/accounts/login", json: payload) }
    }

    /// The account behind a session token; nil when the token is no longer valid. A server or
    /// tunnel error throws like a lost connection: the session must not be dropped over it.
    public func me(token: String) async throws -> Account? {
        let result = try await client.send(request("GET", "/api/accounts/me", token: token))
        if result.status == 401 || result.status == 403 { return nil }
        guard result.isSuccessful else { throw URLError(.badServerResponse) }
        return result.json?.object("account").map(Self.account)
    }

    public func updateProfile(token: String, username: String?, avatarUrl: String?) async -> AuthOutcome {
        var payload: [String: Any] = [:]
        if let username { payload["username"] = username }
        if let avatarUrl { payload["avatarUrl"] = avatarUrl }
        return await outcome { try request("PATCH", "/api/accounts/me", json: payload, token: token) }
    }

    public func uploadAvatar(token: String, dataUrl: String) async -> AuthOutcome {
        await outcome { try request("POST", "/api/accounts/avatar", json: ["dataUrl": dataUrl], token: token) }
    }

    /// Deletes the account for good. Nil on success, else a message the driver can read.
    public func deleteAccount(token: String) async -> String? {
        await simple { try request("DELETE", "/api/accounts/me", token: token) }
    }

    // MARK: Statistics

    public func stats(token: String) async -> AccountStats? {
        guard let result = try? await client.send(request("GET", "/api/accounts/me/stats", token: token)),
              result.isSuccessful,
              let json = result.json
        else { return nil }
        return Self.stats(json)
    }

    public func postTrip(token: String, trip: TripRecord) async -> Bool {
        await succeeds {
            try request("POST", "/api/accounts/me/trips", json: [
                "id": trip.id,
                "startedAt": trip.startedAt,
                "fromLabel": trip.fromLabel,
                "toLabel": trip.toLabel,
                "distanceMeters": trip.distanceMeters,
                "durationSeconds": trip.durationSeconds,
                "alertsCount": trip.alertsCount,
                "topSpeedKmh": trip.topSpeedKmh,
            ], token: token)
        }
    }

    public func postDrive(token: String, seconds: Int, meters: Int) async -> Bool {
        await succeeds { try request("POST", "/api/accounts/me/drive", json: ["seconds": seconds, "meters": meters], token: token) }
    }

    // MARK: Referral codes (admins)

    public func referrals(token: String) async -> [ReferralCode] {
        guard let result = try? await client.send(request("GET", "/api/accounts/referrals", token: token)),
              result.isSuccessful
        else { return [] }
        return (result.json?.objects("referrals") ?? []).map(Self.referral)
    }

    public func createReferral(token: String) async -> ReferralCode? {
        guard let result = try? await client.send(request("POST", "/api/accounts/referrals", json: [:], token: token)),
              result.isSuccessful
        else { return nil }
        return result.json?.object("referral").map(Self.referral)
    }

    // MARK: Email and password

    public func forgot(email: String) async {
        _ = await simple { try request("POST", "/api/accounts/forgot", json: ["email": email]) }
    }

    /// Nil on success, else a message the driver can read.
    public func resetPassword(email: String, code: String, password: String) async -> String? {
        await simple { try request("POST", "/api/accounts/reset", json: ["email": email, "code": code, "password": password]) }
    }

    /// Nil on success, else a message the driver can read.
    public func verify(email: String, code: String) async -> String? {
        await simple { try request("POST", "/api/accounts/verify", json: ["email": email, "code": code]) }
    }

    public func resendVerify(email: String) async {
        _ = await simple { try request("POST", "/api/accounts/resend-verify", json: ["email": email]) }
    }

    // MARK: Plumbing

    private func request(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        json: [String: Any]? = nil,
        token: String? = nil
    ) throws -> URLRequest {
        try client.request(method, client.url(path, query: query), json: json, token: token, timeout: Self.timeout)
    }

    private func outcome(_ make: () throws -> URLRequest) async -> AuthOutcome {
        do {
            let result = try await client.send(make())
            guard result.isSuccessful else { return .failure(Self.friendly(Self.error(in: result))) }
            guard let auth = Self.auth(result.json) else { return .failure("Réponse invalide") }
            return .success(auth)
        } catch {
            return .failure("Réseau indisponible")
        }
    }

    private func succeeds(_ make: () throws -> URLRequest) async -> Bool {
        guard let result = try? await client.send(make()) else { return false }
        return result.isSuccessful
    }

    private func simple(_ make: () throws -> URLRequest) async -> String? {
        do {
            let result = try await client.send(make())
            return result.isSuccessful ? nil : Self.friendly(Self.error(in: result))
        } catch {
            return "Réseau indisponible"
        }
    }

    // MARK: Parsing

    static func auth(_ json: JSON?) -> AuthResult? {
        guard let json, let parsed = json.object("account").map(Self.account) else { return nil }
        return AuthResult(account: parsed, token: json.nonBlankString("token"))
    }

    static func account(_ o: JSON) -> Account {
        Account(
            id: o.string("id"),
            role: Role.fromWire(o.string("role")),
            username: o.nonBlankString("username"),
            displayName: o.nonBlankString("displayName"),
            avatarUrl: o.nonBlankString("avatarUrl"),
            email: o.nonBlankString("email"),
            banned: o.bool("banned"),
            emailVerified: o.bool("emailVerified"),
            access: Access.fromWire(o.string("access")),
            canNavigate: o.has("canNavigate") ? o.bool("canNavigate") : true,
            accessEndsAt: o.nonBlankString("accessEndsAt"),
            trust: o.double("trust", 2.5),
            limits: o.object("limits").map { limits in
                DailyLimits(
                    day: limits.string("day"),
                    reportsPerDay: limits.int("reportsPerDay"),
                    reportsToday: limits.int("reportsToday"),
                    tripsPerDay: limits.int("tripsPerDay"),
                    tripsToday: limits.int("tripsToday")
                )
            }
        )
    }

    static func stats(_ o: JSON) -> AccountStats {
        let totals = o.object("totals") ?? JSON([:])
        let trips = (o.objects("trips") ?? []).map { x in
            TripRecord(
                id: x.string("id"),
                startedAt: x.int("startedAt"),
                fromLabel: x.string("fromLabel"),
                toLabel: x.string("toLabel"),
                distanceMeters: x.int("distanceMeters"),
                durationSeconds: x.int("durationSeconds"),
                alertsCount: x.int("alertsCount"),
                topSpeedKmh: x.int("topSpeedKmh")
            )
        }
        return AccountStats(
            tripCount: totals.int("tripCount"),
            distanceMeters: totals.int("distanceMeters"),
            driveSeconds: totals.int("driveDurationSeconds"),
            alertsTraversed: totals.int("alertsTraversed"),
            reportsDeclared: totals.int("reportsDeclared"),
            reportsConfirmed: totals.int("reportsConfirmed"),
            trust: o.double("trust", 2.5),
            trips: trips
        )
    }

    static func referral(_ o: JSON) -> ReferralCode {
        ReferralCode(code: o.string("code"), createdAt: o.string("createdAt"), months: o.int("months", 6), redemptions: o.int("redemptions"))
    }

    static func error(in result: HTTPResult) -> String {
        result.json?.nonBlankString("error") ?? "Erreur"
    }

    /// The backend's error, in words the driver reads.
    static func friendly(_ error: String) -> String {
        if error.contains("taken") { return "Ce pseudo est déjà pris." }
        if error.contains("invalid username") { return "Pseudo invalide (3–20 caractères : lettres, chiffres, _ .)." }
        if error.contains("email already") { return "Cet email est déjà utilisé." }
        if error.contains("invalid email") { return "Email invalide." }
        if error.contains("password too short") { return "Mot de passe trop court (8 caractères min)." }
        if error.contains("invalid credentials") { return "Identifiant ou mot de passe incorrect." }
        if error.contains("banned") { return "Ce compte est banni." }
        if error.contains("invalid referral") { return "Code de parrainage invalide." }
        if error.contains("subscription required") { return "Abonnement requis." }
        return error.prefix(1).uppercased() + error.dropFirst()
    }
}
