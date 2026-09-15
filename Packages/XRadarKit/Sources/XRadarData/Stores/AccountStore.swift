import Foundation
import Observation
import XRadarCore

/// Where secrets live: the Keychain in the app, memory in tests.
@MainActor
public protocol SecretStore {
    func string(for key: String) -> String?
    func set(_ value: String?, for key: String)
}

/// Identity and session, as the Android AccountRepository keeps them. A per-install device id
/// (in the Keychain, so it survives a reinstall) restores a session; a chosen username (guest)
/// or email and password (member) completes onboarding. The token (Keychain) and the last
/// account (UserDefaults) are cached so the app opens without a flash.
@MainActor
@Observable
public final class AccountStore {
    public private(set) var account: Account?
    public private(set) var token: String?
    public private(set) var deviceId = ""

    private let api: AccountAPI
    private let secrets: any SecretStore
    private let defaults: UserDefaults

    public init(api: AccountAPI, secrets: any SecretStore, defaults: UserDefaults = .standard) {
        self.api = api
        self.secrets = secrets
        self.defaults = defaults
    }

    public var role: Role {
        account?.role ?? .guest
    }

    /// This phone's id, created once.
    @discardableResult
    public func ensureDeviceId() -> String {
        if !deviceId.isEmpty { return deviceId }
        if let stored = secrets.string(for: Keys.device) {
            deviceId = stored
        } else {
            deviceId = UUID().uuidString.lowercased()
            secrets.set(deviceId, for: Keys.device)
        }
        return deviceId
    }

    /// Loads the cached session synchronously so the first screen renders immediately.
    public func restore() {
        ensureDeviceId()
        token = secrets.string(for: Keys.token)
        if let data = defaults.data(forKey: Keys.account),
           let stored = try? JSONDecoder().decode(StoredAccount.self, from: data) {
            account = stored.account
        }
    }

    /// Refresh from the backend: validate the token, else restore the session of this device.
    /// Offline, the cached session stays as it is.
    public func refresh() async {
        let id = ensureDeviceId()
        if let current = token {
            do {
                if let fresh = try await api.me(token: current) {
                    store(fresh, token: current)
                    return
                }
                setToken(nil) // the token is no longer valid
            } catch {
                return
            }
        }
        if let auth = await api.authDevice(deviceId: id) {
            store(auth.account, token: auth.token)
        }
    }

    public func usernameAvailable(_ username: String) async throws -> Bool {
        try await api.usernameAvailable(username)
    }

    public func claimGuest(username: String, password: String) async -> AuthOutcome {
        apply(await api.claimGuest(deviceId: deviceId, username: username, password: password))
    }

    public func register(email: String, password: String, username: String, referralCode: String? = nil) async -> AuthOutcome {
        apply(await api.register(email: email, password: password, username: username, referralCode: referralCode))
    }

    /// Email (member) or username (guest), and the password; the account then sticks to this phone.
    public func login(identifier: String, password: String) async -> AuthOutcome {
        apply(await api.login(identifier: identifier, password: password, deviceId: deviceId))
    }

    public func stats() async -> AccountStats? {
        guard let token else { return nil }
        return await api.stats(token: token)
    }

    public func postTrip(_ trip: TripRecord) async -> Bool {
        guard let token else { return false }
        return await api.postTrip(token: token, trip: trip)
    }

    public func postDrive(seconds: Int, meters: Int) async -> Bool {
        guard let token else { return false }
        return await api.postDrive(token: token, seconds: seconds, meters: meters)
    }

    public func referrals() async -> [ReferralCode] {
        guard let token else { return [] }
        return await api.referrals(token: token)
    }

    public func createReferral() async -> ReferralCode? {
        guard let token else { return nil }
        return await api.createReferral(token: token)
    }

    /// Re-read the account (access can change: trial ending, referral…).
    public func reload() async {
        guard let current = token, let fresh = try? await api.me(token: current) else { return }
        store(fresh, token: current)
    }

    public func updateProfile(username: String? = nil, avatarUrl: String? = nil) async -> AuthOutcome {
        guard let token else { return .failure("Non connecté") }
        return apply(await api.updateProfile(token: token, username: username, avatarUrl: avatarUrl))
    }

    public func uploadAvatar(dataUrl: String) async -> AuthOutcome {
        guard let token else { return .failure("Non connecté") }
        return apply(await api.uploadAvatar(token: token, dataUrl: dataUrl))
    }

    public func forgot(email: String) async {
        await api.forgot(email: email)
    }

    public func resetPassword(email: String, code: String, password: String) async -> String? {
        await api.resetPassword(email: email, code: code, password: password)
    }

    /// Nil on success (the account is then re-read for its verified flag), else a message.
    public func verifyEmail(code: String) async -> String? {
        guard let email = account?.email else { return "Aucun email" }
        let error = await api.verify(email: email, code: code)
        if error == nil { await reload() }
        return error
    }

    public func resendVerify() async {
        guard let email = account?.email else { return }
        await api.resendVerify(email: email)
    }

    public func logout() {
        setToken(nil)
        account = nil
        defaults.removeObject(forKey: Keys.account)
    }

    /// Deletes the account on the server, then forgets the session here (the phone keeps its id).
    /// Nil on success, else a message the driver can read.
    public func deleteAccount() async -> String? {
        guard let token else { return "Non connecté" }
        if let error = await api.deleteAccount(token: token) { return error }
        logout()
        return nil
    }

    // MARK: Storage

    @discardableResult
    private func apply(_ outcome: AuthOutcome) -> AuthOutcome {
        if case .success(let auth) = outcome {
            store(auth.account, token: auth.token)
        }
        return outcome
    }

    private func store(_ fresh: Account, token newToken: String?) {
        account = fresh
        if let newToken { setToken(newToken) }
        if let data = try? JSONEncoder().encode(StoredAccount(fresh)) {
            defaults.set(data, forKey: Keys.account)
        }
    }

    private func setToken(_ value: String?) {
        token = value
        secrets.set(value, for: Keys.token)
    }

    private enum Keys {
        static let device = "device_id"
        static let token = "session_token"
        static let account = "xr_identity.account"
    }
}

/// The account as cached on the phone.
struct StoredAccount: Codable {
    let id: String
    let role: String
    let username: String?
    let displayName: String?
    let avatarUrl: String?
    let email: String?
    let banned: Bool
    let emailVerified: Bool
    let access: String
    let canNavigate: Bool
    let accessEndsAt: String?
    let trust: Double

    init(_ account: Account) {
        id = account.id
        switch account.role {
        case .guest: role = "guest"
        case .client: role = "client"
        case .admin: role = "admin"
        }
        username = account.username
        displayName = account.displayName
        avatarUrl = account.avatarUrl
        email = account.email
        banned = account.banned
        emailVerified = account.emailVerified
        switch account.access {
        case .trial: access = "trial"
        case .active: access = "active"
        case .restricted: access = "restricted"
        }
        canNavigate = account.canNavigate
        accessEndsAt = account.accessEndsAt
        trust = account.trust
    }

    var account: Account {
        Account(
            id: id,
            role: .fromWire(role),
            username: username,
            displayName: displayName,
            avatarUrl: avatarUrl,
            email: email,
            banned: banned,
            emailVerified: emailVerified,
            access: .fromWire(access),
            canNavigate: canNavigate,
            accessEndsAt: accessEndsAt,
            trust: trust
        )
    }
}
