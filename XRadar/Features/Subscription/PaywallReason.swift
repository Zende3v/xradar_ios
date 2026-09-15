import XRadarCore
import XRadarData

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
        case .restricted: account?.role == .client ? "Ton abonnement est terminé" : "Ton essai gratuit est terminé"
        case .reportLimit: "Signalements du jour utilisés"
        case .tripLimit: "Trajets du jour utilisés"
        case .music: "Musique réservée aux membres"
        case .photo: "Photo de profil réservée aux membres"
        }
    }

    func message(for account: Account?) -> String {
        switch self {
        case .restricted:
            "La carte reste disponible. Abonne-toi pour retrouver la navigation, les alertes et les signalements."
        case .reportLimit:
            "Un compte invité peut signaler \(account?.limits?.reportsPerDay ?? 5) fois par jour. Les membres signalent sans limite."
        case .tripLimit:
            "Un compte invité peut lancer \(account?.limits?.tripsPerDay ?? 7) trajets par jour. Les membres naviguent sans limite."
        case .music:
            "Le raccourci Apple Music pendant la conduite fait partie de l'abonnement."
        case .photo:
            "Ajoute ta photo de profil avec l'abonnement membre."
        }
    }
}
