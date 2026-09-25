import Foundation
import EonaCore

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
    /// What the code grants once used, in months of client access.
    public let months: Int
    public let redemptions: Int
    /// Usable right now: not revoked, not past its date.
    public let active: Bool
    /// How long it was given when minted, and when it stops working.
    public let validityMonths: Int?
    public let expiresAt: Date?
    public let revokedAt: Date?
    /// What happened to it: created, extended, revoked, regenerated.
    public let history: [ReferralEvent]

    public init(
        code: String,
        createdAt: String,
        months: Int,
        redemptions: Int,
        active: Bool = true,
        validityMonths: Int? = nil,
        expiresAt: Date? = nil,
        revokedAt: Date? = nil,
        history: [ReferralEvent] = []
    ) {
        self.code = code
        self.createdAt = createdAt
        self.months = months
        self.redemptions = redemptions
        self.active = active
        self.validityMonths = validityMonths
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.history = history
    }

    /// "dans 3 mois", "dans 12 jours", "expiré" — what an admin reads at a glance.
    public var remainingLabel: String {
        guard let expiresAt else { return "sans date de fin" }
        let seconds = expiresAt.timeIntervalSinceNow
        if seconds <= 0 { return "expiré" }
        let days = Int(seconds / 86_400)
        if days >= 60 { return "dans \(days / 30) mois" }
        if days >= 1 { return "dans \(days) jour" + (days > 1 ? "s" : "") }
        return "aujourd'hui"
    }
}

/// One line in a code's history: what was done, by whom, when.
public struct ReferralEvent: Sendable, Hashable {
    public let action: String
    public let by: String
    public let at: Date?

    public init(action: String, by: String, at: Date?) {
        self.action = action
        self.by = by
        self.at = at
    }

    /// "prolongé", "révoqué"… as an admin says it.
    public var label: String {
        switch action {
        case "created": "créé"
        case "extended": "prolongé"
        case "revoked": "révoqué"
        case "regenerated": "régénéré"
        case "replaces": "remplace un code"
        default: action
        }
    }
}

/// The duration new codes get, and the range an admin may choose from.
public struct ReferralSettings: Sendable, Hashable {
    public let validityMonths: Int
    public let minMonths: Int
    public let maxMonths: Int

    public init(validityMonths: Int, minMonths: Int, maxMonths: Int) {
        self.validityMonths = validityMonths
        self.minMonths = minMonths
        self.maxMonths = maxMonths
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

    /// Whether [username] is free. Signed in ([token]), a name the driver left lately counts as
    /// theirs again. Nil when the backend could not say.
    public func usernameAvailability(_ username: String, token: String?) async -> UsernameAvailability? {
        guard let call = try? request("GET", "/api/accounts/username-available", query: [URLQueryItem("u", username)], token: token),
              let result = try? await client.send(call),
              result.isSuccessful,
              let json = result.json
        else { return nil }
        return .fromWire(available: json.bool("available"), reason: json.nonBlankString("reason"))
    }

    /// Device sign-in, restoring the session bound to this phone; nil when it fails.
    public func authDevice(deviceId: String, app: [String: String] = [:]) async -> AuthResult? {
        var payload: [String: Any] = ["deviceId": deviceId, "platform": Self.platform]
        if !app.isEmpty { payload["app"] = app }
        guard let result = try? await client.send(request("POST", "/api/accounts/auth", json: payload)),
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

    public func register(
        email: String,
        password: String,
        username: String,
        referralCode: String?,
        app: [String: String] = [:]
    ) async -> AuthOutcome {
        var payload: [String: Any] = ["email": email, "password": password, "username": username]
        if let code = referralCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            payload["referralCode"] = code
        }
        // What the app knows of itself, for the admin card: nothing read behind the driver's back.
        if !app.isEmpty { payload["app"] = app }
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

    /// Whether the other members of a group trip see this driver's statistics on their card.
    public func setGroupStatsVisible(_ visible: Bool, token: String) async -> AuthOutcome {
        await outcome { try request("PATCH", "/api/accounts/me/privacy", json: ["groupStatsVisible": visible], token: token) }
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
        var payload: [String: Any] = [
            "id": trip.id,
            "startedAt": trip.startedAt,
            "fromLabel": trip.fromLabel,
            "toLabel": trip.toLabel,
            "distanceMeters": trip.distanceMeters,
            "durationSeconds": trip.durationSeconds,
            "alertsCount": trip.alertsCount,
            "topSpeedKmh": trip.topSpeedKmh,
            "stops": trip.stops,
            "stoppedSeconds": trip.stoppedSeconds,
            "events": Self.wireEvents(trip.events),
        ]
        if let planned = trip.plannedSeconds { payload["plannedSeconds"] = planned }
        // The ETA and route measures, for a trip recorded with them.
        if let measure = trip.measure {
            for (key, value) in Self.wireMeasure(measure) {
                payload[key] = value
            }
        }
        return await succeeds {
            try request("POST", "/api/accounts/me/trips", json: payload, token: token)
        }
    }

    public func postDrive(token: String, seconds: Int, meters: Int) async -> Bool {
        await succeeds { try request("POST", "/api/accounts/me/drive", json: ["seconds": seconds, "meters": meters], token: token) }
    }

    /// The version of the terms accepted, and when: the backend stamps the moment itself.
    public func recordTerms(token: String, version: String) async -> Bool {
        await succeeds { try request("POST", "/api/accounts/me/terms", json: ["version": version], token: token) }
    }

    // MARK: Sign in with Google

    /// The identity token from Google, checked on the server. Never trusted here.
    public func signInWithGoogle(idToken: String, deviceId: String?, app: [String: String]) async -> AuthOutcome {
        var json: [String: Any] = ["idToken": idToken, "app": app]
        if let deviceId, !deviceId.isEmpty { json["deviceId"] = deviceId }
        guard let request = try? request("POST", "/api/accounts/google", json: json),
              let result = try? await client.send(request)
        else { return .failure("Connexion impossible pour l'instant.") }
        guard result.isSuccessful, let json = result.json,
              let account = json.object("account").map(Self.account),
              let token = json.nonBlankString("token")
        else { return .failure(Self.friendly(Self.error(in: result))) }
        return .success(AuthResult(account: account, token: token))
    }

    /// Ties a Google account to the one signed in; nil when it went through.
    public func linkGoogle(idToken: String, token: String) async -> String? {
        guard let request = try? request("POST", "/api/accounts/me/link/google", json: ["idToken": idToken], token: token),
              let result = try? await client.send(request)
        else { return "Liaison impossible pour l'instant." }
        return result.isSuccessful ? nil : Self.friendly(Self.error(in: result))
    }

    /// Unties it; nil when it went through.
    public func unlinkGoogle(token: String) async -> String? {
        guard let request = try? request("DELETE", "/api/accounts/me/link/google", token: token),
              let result = try? await client.send(request)
        else { return "Dissociation impossible pour l'instant." }
        return result.isSuccessful ? nil : Self.friendly(Self.error(in: result))
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

    /// How long new codes stay usable, and the range an admin may pick from.
    public func referralSettings(token: String) async -> ReferralSettings? {
        guard let result = try? await client.send(request("GET", "/api/accounts/referrals/settings", token: token)),
              result.isSuccessful, let json = result.json?.object("settings")
        else { return nil }
        return ReferralSettings(
            validityMonths: json.int("referralValidityMonths", 3),
            minMonths: json.int("referralValidityMinMonths", 1),
            maxMonths: json.int("referralValidityMaxMonths", 12)
        )
    }

    /// Sets the duration for the codes minted from now on; the ones already out keep their date.
    @discardableResult
    public func setReferralValidity(months: Int, token: String) async -> Bool {
        guard let request = try? request("PUT", "/api/accounts/referrals/settings", json: ["validityMonths": months], token: token),
              let result = try? await client.send(request)
        else { return false }
        return result.isSuccessful
    }

    /// "extend" (with months), "revoke" or "regenerate" on one code.
    public func actOnReferral(code: String, action: String, months: Int? = nil, token: String) async -> ReferralCode? {
        var json: [String: Any] = ["action": action]
        if let months { json["months"] = months }
        guard let request = try? request("PATCH", "/api/accounts/referrals/(BackendClient.segment(code))", json: json, token: token),
              let result = try? await client.send(request), result.isSuccessful
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
            },
            canChangeUsername: o.bool("canChangeUsername"),
            usernameChangeableAt: o.nonBlankString("usernameChangeableAt"),
            signupMethod: o.nonBlankString("signupMethod"),
            providers: (o.objects("providers") ?? []).compactMap { $0.nonBlankString("provider") },
            hasPassword: o.bool("hasPassword", true),
            groupStatsVisible: o.bool("groupStatsVisible", true)
        )
    }

    /// A trip's events as the backend keeps them: counts by kind name.
    static func wireEvents(_ events: [AlertType: Int]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: events.map { ($0.key.wireName, $0.value) })
    }

    /// A trip's ETA and route measures under the backend's names (D1.7): no coordinates, and an
    /// unknown value as JSON null.
    static func wireMeasure(_ measure: TripMeasure) -> [String: Any] {
        [
            "arrived": measure.arrived,
            "departedAt": orNull(measure.departedAt),
            "manualStart": measure.manualStart,
            "plannedMeters": orNull(measure.plannedMeters),
            "pausedSeconds": measure.pausedSeconds,
            "uncertainSeconds": measure.uncertainSeconds,
            "etaChecks": measure.etaChecks.map { check -> [String: Int] in
                [
                    "at": check.at,
                    "shownAt": check.shownAt,
                    "arrivalAt": check.arrivalAt,
                    "pausedBefore": check.pausedBefore,
                    "uncertainBefore": check.uncertainBefore,
                ]
            },
            "recalcCount": measure.recalcCount,
            "fasterCount": measure.fasterCount,
            "engines": measure.engines,
            "mapVersion": orNull(measure.mapVersion),
            "appVersion": measure.appVersion,
            "platform": measure.platform,
            "etaMode": measure.etaMode,
            "trafficSources": measure.trafficSources,
            "retargeted": measure.retargeted ?? false,
        ]
    }

    /// A trip's events read back; unknown kinds and empty counts are left out.
    static func events(_ o: JSON?) -> [AlertType: Int] {
        guard let o else { return [:] }
        var events: [AlertType: Int] = [:]
        for type in AlertType.allCases where o.has(type.wireName) {
            let count = o.int(type.wireName)
            if count > 0 { events[type] = count }
        }
        return events
    }

    /// A trip's ETA and route measures read back, as Android reads them; nil for a trip sent
    /// before them (no "etaMode").
    static func measure(_ o: JSON) -> TripMeasure? {
        guard !o.isNull("etaMode") else { return nil }
        return TripMeasure(
            arrived: o.bool("arrived"),
            departedAt: o.isNull("departedAt") ? nil : o.int("departedAt"),
            manualStart: o.bool("manualStart"),
            plannedMeters: o.isNull("plannedMeters") ? nil : o.int("plannedMeters"),
            pausedSeconds: o.int("pausedSeconds"),
            uncertainSeconds: o.int("uncertainSeconds"),
            etaChecks: (o.objects("etaChecks") ?? []).map { c in
                EtaCheck(
                    at: c.int("at"),
                    shownAt: c.int("shownAt"),
                    arrivalAt: c.int("arrivalAt"),
                    pausedBefore: c.int("pausedBefore"),
                    uncertainBefore: c.int("uncertainBefore")
                )
            },
            recalcCount: o.int("recalcCount"),
            fasterCount: o.int("fasterCount"),
            engines: o.strings("engines"),
            mapVersion: o.nonBlankString("mapVersion"),
            appVersion: o.string("appVersion"),
            platform: o.string("platform"),
            etaMode: o.string("etaMode"),
            trafficSources: o.strings("trafficSources"),
            retargeted: o.bool("retargeted")
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
                topSpeedKmh: x.int("topSpeedKmh"),
                plannedSeconds: x.has("plannedSeconds") && !x.isNull("plannedSeconds") ? x.int("plannedSeconds") : nil,
                stops: x.int("stops"),
                stoppedSeconds: x.int("stoppedSeconds"),
                events: Self.events(x.object("events")),
                measure: Self.measure(x)
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
        ReferralCode(
            code: o.string("code"),
            createdAt: o.string("createdAt"),
            months: o.int("months", 6),
            redemptions: o.int("redemptions"),
            active: o.bool("active", true),
            validityMonths: o.isNull("validityMonths") ? nil : o.int("validityMonths"),
            expiresAt: iso(o.nonBlankString("expiresAt")),
            revokedAt: iso(o.nonBlankString("revokedAt")),
            history: (o.objects("history") ?? []).map { event in
                ReferralEvent(action: event.string("action"), by: event.string("by"), at: iso(event.nonBlankString("at")))
            }
        )
    }

    /// The backend writes dates with fractional seconds; the plain reader refuses them.
    static func iso(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func error(in result: HTTPResult) -> String {
        result.json?.nonBlankString("error") ?? "Erreur"
    }

    /// The backend's error, in words the driver reads.
    static func friendly(_ error: String) -> String {
        if error.contains("taken") { return "Ce pseudo est déjà pris." }
        if error.contains("reserved") { return "Ce pseudo est réservé." }
        if error.contains("change too soon") { return "Un seul changement de pseudo par semaine." }
        if error.contains("clients only") { return "Réservé aux membres avec un accès actif." }
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
