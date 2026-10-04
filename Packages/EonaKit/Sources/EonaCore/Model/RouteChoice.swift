import Foundation

/// Choix d'itinéraire (02/10). Valeur brute échangée avec le backend (`preference`).
public enum RoutePreference: String, Sendable, Hashable, CaseIterable {
    /// Rapide : le plus rapide, bouchons évités en route.
    case fastest
    /// Éco : le plus court en distance.
    case shortest
}

/// Une option du choix : en calcul, prête, ou indisponible (échec, backend sans Éco).
public enum RouteOption: Sendable, Hashable {
    case loading
    case ready(Route)
    case unavailable

    public var route: Route? {
        if case .ready(let route) = self { return route }
        return nil
    }
}

/// Choix d'itinéraire vers [destination] : Rapide, Éco, choix retenu.
public struct RouteChoice: Sendable, Hashable {
    public let destination: Place
    public var fastest: RouteOption
    public var shortest: RouteOption
    public var selected: RoutePreference

    public init(destination: Place, fastest: RouteOption = .loading, shortest: RouteOption = .loading, selected: RoutePreference = .fastest) {
        self.destination = destination
        self.fastest = fastest
        self.shortest = shortest
        self.selected = selected
    }

    public func option(_ preference: RoutePreference) -> RouteOption {
        switch preference {
        case .fastest: fastest
        case .shortest: shortest
        }
    }

    /// Route du choix retenu, prête ; nil sinon.
    public var chosenRoute: Route? {
        option(selected).route
    }

    /// Aucune route obtenue : erreur, nouvel essai proposé.
    public var failed: Bool {
        fastest == .unavailable && shortest == .unavailable
    }

    /// Calcul encore en cours.
    public var loading: Bool {
        fastest == .loading || shortest == .loading
    }

    /// Option retenue indisponible : choix passe sur l'autre, prête. Sinon inchangé.
    public mutating func keepUsableSelection() {
        if option(selected) == .unavailable, let other = RoutePreference.allCases.first(where: { option($0).route != nil }) {
            selected = other
        }
    }
}

public extension Route {
    /// Temps annoncé : HERE avec trafic quand connu, sinon moteur.
    var expectedSeconds: Int {
        trafficSeconds ?? durationSeconds
    }
}

/// Textes du choix d'itinéraire.
public enum RouteChoiceText {
    /// Écart sous lequel Éco et Rapide sont un même trajet : 1 % de la distance, 100 m au moins.
    static let sameRouteShare = 0.01
    static let sameRouteMinMeters = 100

    /// "8 min", "1 h 05". Jamais "0 min".
    public static func duration(_ seconds: Int) -> String {
        let minutes = max(roundToInt(Double(seconds) / 60.0), 1)
        return minutes >= 60 ? "\(minutes / 60) h \(twoDigits(minutes % 60))" : "\(minutes) min"
    }

    /// "24,8 km", "850 m".
    public static func distance(_ meters: Int) -> String {
        TripInfo.distanceLabel(meters: Double(meters))
    }

    /// Heure d'arrivée "18:42" en partant à [now].
    public static func arrival(_ route: Route, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        let clock = gregorianCalendar(in: timeZone).dateComponents([.hour, .minute], from: now.addingTimeInterval(Double(route.expectedSeconds)))
        return "\(twoDigits(clock.hour ?? 0)):\(twoDigits(clock.minute ?? 0))"
    }

    /// Éco et Rapide au même tracé, à l'arrondi près.
    public static func same(_ eco: Route, _ fastest: Route) -> Bool {
        let gap = abs(eco.distanceMeters - fastest.distanceMeters)
        return gap <= max(sameRouteMinMeters, Int(Double(fastest.distanceMeters) * sameRouteShare))
    }

    /// Ligne sous Éco, face à Rapide : "3,2 km de moins · 4 min de plus".
    public static func eco(_ eco: Route, against fastest: Route?) -> String {
        guard let fastest else { return "Le plus court en distance" }
        if same(eco, fastest) { return "Même trajet que Rapide" }
        let saved = fastest.distanceMeters - eco.distanceMeters
        let lost = eco.expectedSeconds - fastest.expectedSeconds
        let distance = saved > 0 ? "\(Self.distance(saved)) de moins" : "Le plus court en distance"
        let minutes = roundToInt(Double(lost) / 60.0)
        return minutes >= 1 ? "\(distance) · \(minutes) min de plus" : "\(distance) · aussi rapide"
    }

    /// Étapes du choix : "Via Boulangerie", "Via Boulangerie +2".
    public static func via(_ names: [String]) -> String {
        guard let first = names.first else { return "" }
        return names.count > 1 ? "Via \(first) +\(names.count - 1)" : "Via \(first)"
    }

    /// Bandeau en route : "1 étape · Boulangerie", "3 étapes · Boulangerie" (la prochaine).
    public static func stops(_ names: [String]) -> String {
        guard let next = names.first else { return "Étape" }
        return "\(names.count) étape\(names.count > 1 ? "s" : "") · \(next)"
    }

    /// Ligne sous Rapide, face à Éco : "6 min de moins · bouchons évités".
    public static func fastest(_ fastest: Route, against eco: Route?) -> String {
        guard let eco, !same(eco, fastest) else { return "Bouchons évités en route" }
        let minutes = roundToInt(Double(eco.expectedSeconds - fastest.expectedSeconds) / 60.0)
        return minutes >= 1 ? "\(minutes) min de moins · bouchons évités" : "Bouchons évités en route"
    }
}
