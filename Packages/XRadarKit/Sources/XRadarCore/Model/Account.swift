import Foundation

/// Account role. Guest = free trial (7 days) then restricted until they pay; client = paying
/// subscriber (or referral); admin = full access.
public enum Role: Int, Sendable, Hashable, CaseIterable, Comparable {
    case guest
    case client
    case admin

    public var label: String {
        switch self {
        case .guest: "Invité"
        case .client: "Membre"
        case .admin: "Admin"
        }
    }

    public static func fromWire(_ value: String?) -> Role {
        switch value {
        case "admin"?: .admin
        case "client"?: .client
        default: .guest
        }
    }

    public static func < (lhs: Role, rhs: Role) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Where the account stands with regard to access, as the backend computes it.
public enum Access: Sendable, Hashable {
    /// Guest within the 7 free days.
    case trial
    /// Client with a running subscription, or admin.
    case active
    /// Trial over / subscription lapsed: map only, no navigation, no reporting.
    case restricted

    public static func fromWire(_ value: String?) -> Access {
        switch value {
        case "active"?: .active
        case "restricted"?: .restricted
        default: .trial
        }
    }
}

/// The signed-in account.
public struct Account: Sendable, Hashable {
    public let id: String
    public let role: Role
    public let username: String?
    public let displayName: String?
    public let avatarUrl: String?
    public let email: String?
    public let banned: Bool
    public let emailVerified: Bool
    public let access: Access
    /// False once the trial or the subscription has run out.
    public let canNavigate: Bool
    /// End of the trial (guest) or of the subscription (client), ISO-8601; nil = none.
    public let accessEndsAt: String?
    /// "Note de confiance", 0...5: how often this driver's reports get confirmed.
    public let trust: Double
    /// A guest's daily limits and today's use; nil for clients and admins, who have none.
    public let limits: DailyLimits?

    public init(
        id: String,
        role: Role,
        username: String?,
        displayName: String?,
        avatarUrl: String?,
        email: String?,
        banned: Bool,
        emailVerified: Bool = false,
        access: Access = .trial,
        canNavigate: Bool = true,
        accessEndsAt: String? = nil,
        trust: Double = 2.5,
        limits: DailyLimits? = nil
    ) {
        self.id = id
        self.role = role
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.email = email
        self.banned = banned
        self.emailVerified = emailVerified
        self.access = access
        self.canNavigate = canNavigate
        self.accessEndsAt = accessEndsAt
        self.trust = trust
        self.limits = limits
    }

    /// A finished onboarding = has a chosen username.
    public var isOnboarded: Bool {
        !(username?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// Profile pictures and renames are for members.
    public var canEditProfile: Bool {
        role == .client || role == .admin
    }

    public var isRestricted: Bool {
        access == .restricted || !canNavigate
    }

    /// A client whose subscription runs, or an admin.
    public var isSubscriber: Bool {
        (role == .client || role == .admin) && !isRestricted
    }
}
