import EonaCore
import EonaData

/// Why the offers show: the account is blocked, a guest reached a limit of the day, or the
/// action is a members' feature.
enum PaywallReason: String, Identifiable {
    case restricted
    case reportLimit
    case tripLimit
    case taxi
    case truck
    case groups
    case colours
    case lights
    case photo
    case username

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
        case .restricted: "Découvre EONA+"
        case .reportLimit: "Signalements du jour utilisés"
        case .tripLimit: "Trajets du jour utilisés"
        case .taxi: "Taxi avec EONA+"
        case .truck: "Camion avec EONA+"
        case .groups: "Rouler ensemble avec EONA+"
        case .colours: "Tes couleurs avec EONA+"
        case .lights: "Feux en direct avec EONA+"
        case .photo: "Crée ton compte"
        case .username: "Choisis ton pseudo"
        }
    }

    func message(for account: Account?) -> String {
        switch self {
        case .restricted:
            "Accès gratuit permanent : quatre trajets quotidiens. EONA+ ouvre trajets illimités et options supplémentaires."
        case .reportLimit:
            "Invité : \(account?.limits?.reportsPerDay ?? 5) signalements par jour. Illimité avec EONA +."
        case .tripLimit:
            "Quatre trajets quotidiens utilisés. Reprise demain, minuit Paris. EONA+ ouvre trajets illimités."
        case .taxi:
            "Profil Taxi : voies réservées autorisées aux taxis, selon cartographie disponible."
        case .truck:
            "Curseur Camion inclus dans EONA+."
        case .groups:
            "Partage un trajet entre cinq conducteurs. Position, progression et arrivée réunies sur carte."
        case .colours:
            "Personnalise boutons, tracé et curseur parmi onze couleurs."
        case .lights:
            "Timer réservé EONA+. Fonction en préparation, compte à rebours actuellement indisponible."
        case .photo:
            "Compte gratuit : photo de profil et historique conservé. Sept jours EONA+ offerts après inscription."
        case .username:
            "Inscris-toi avec pseudo, email et mot de passe. Sept jours EONA+ offerts."
        }
    }
}
