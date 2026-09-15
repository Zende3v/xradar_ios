import Foundation

/// The backend refused an action for the account's access: the trial or the subscription is
/// over, or a guest used up today's reports or trips.
public enum AccessDenial: Error, Sendable, Hashable {
    case subscriptionRequired
    case dailyReportLimit
    case dailyTripLimit

    /// The refusal [result] carries, if it is one.
    static func of(_ result: HTTPResult) -> AccessDenial? {
        guard result.status == 403 || result.status == 429 else { return nil }
        switch result.json?.string("error") {
        case "subscription required"?: return .subscriptionRequired
        case "daily report limit"?: return .dailyReportLimit
        case "daily trip limit"?: return .dailyTripLimit
        default: return nil
        }
    }
}
