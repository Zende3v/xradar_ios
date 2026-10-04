import EonaCore
import EonaData

/// Why the offers show: the account is blocked, a guest reached a limit of the day, or the
/// action is a members' feature.
enum PaywallReason: String, Identifiable {
    case restricted
    case reportLimit
    case tripLimit
    case music
    case photo

    var id: Self { self }

    init(_ denial: AccessDenial) {
        switch denial {
        case .subscriptionRequired: self = .restricted
        case .dailyReportLimit: self = .reportLimit
        case .dailyTripLimit: self = .tripLimit
        }
    }

    func title(for account: Account?) -> String {
        switch self {
        case .restricted: account?.role == .client ? "Ton EONA + est terminé" : "Ton essai gratuit est terminé"
        case .reportLimit: "Signalements du jour utilisés"
        case .tripLimit: "Trajets du jour utilisés"
        case .music: "Musique avec EONA +"
        case .photo: "Photo avec EONA +"
        }
    }

    func message(for account: Account?) -> String {
        switch self {
        case .restricted:
            "La carte reste disponible. EONA + rouvre navigation, alertes et signalements."
        case .reportLimit:
            "Invité : \(account?.limits?.reportsPerDay ?? 5) signalements par jour. Illimité avec EONA +."
        case .tripLimit:
            "Invité : \(account?.limits?.tripsPerDay ?? 7) trajets par jour. Illimité avec EONA +."
        case .music:
            "Le raccourci Apple Music au volant est inclus dans EONA +."
        case .photo:
            "Photo de profil incluse dans EONA +."
        }
    }
}
