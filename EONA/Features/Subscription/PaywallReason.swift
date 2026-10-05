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
        case .restricted: "EONA+"
        case .reportLimit: "Signalements du jour utilisés"
        case .tripLimit: "Trajets du jour utilisés"
        case .taxi: "EONA Taxi"
        case .truck: "EONA Poids lourd"
        case .groups: "Trajet en groupe"
        case .colours: "Thème"
        case .lights: "Feux en direct"
        case .photo: "Photo de profil"
        case .username: "Pseudo"
        }
    }

    func message(for account: Account?) -> String {
        switch self {
        case .restricted:
            "4 trajets par jour en gratuit. Trajets illimités avec EONA+."
        case .reportLimit:
            "Limite quotidienne atteinte. Reprise à minuit, heure de Paris."
        case .tripLimit:
            "4 trajets utilisés. Reprise à minuit, heure de Paris."
        case .taxi:
            "Voies autorisées aux taxis, selon cartographie."
        case .truck:
            "Itinéraires adaptés au gabarit et aux restrictions de votre véhicule."
        case .groups:
            "Jusqu'à 5 conducteurs. Position et arrivée partagées."
        case .colours:
            "11 couleurs pour tracé, curseur et commandes."
        case .lights:
            "Temps restant avant le changement des feux sur votre trajet."
        case .photo:
            "Photo de profil, historique conservé. 7 jours EONA+ offerts."
        case .username:
            "Pseudo, email, mot de passe. 7 jours EONA+ offerts."
        }
    }
}
