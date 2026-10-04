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

    /// Rapide = moins de temps avec trafic. Valhalla choisit Rapide sans trafic : Éco chronométré
    /// plus vite par HERE (les deux temps HERE connus) prend aussi place de Rapide. Éco, plus court
    /// et plus rapide, domine. Aucun appel en plus.
    public mutating func keepFastestByTraffic() {
        guard let fast = fastest.route, let eco = shortest.route,
              let fastSeconds = fast.trafficSeconds, let ecoSeconds = eco.trafficSeconds,
              ecoSeconds < fastSeconds
        else { return }
        fastest = .ready(eco)
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

/// Coût carburant estimé d'un trajet : consommation des réglages, prix médian des stations
/// proches pour le carburant préféré.
public struct FuelEstimate: Sendable, Hashable {
    public let litresPer100: Double
    public let eurosPerLitre: Double

    public init(litresPer100: Double, eurosPerLitre: Double) {
        self.litresPer100 = litresPer100
        self.eurosPerLitre = eurosPerLitre
    }

    /// Euros pour [meters].
    public func cost(meters: Int) -> Double {
        Double(max(meters, 0)) / 100_000 * litresPer100 * eurosPerLitre
    }

    /// Prix médian de [fuel] parmi [places] : en vente, mis à jour sous 96 h. Nil sans prix.
    public static func medianPrice(_ fuel: FuelType, in places: [Place], nowMillis: Int) -> Double? {
        let prices = places.compactMap { $0.shownFuelPrice(fuel, nowMillis: nowMillis) }.sorted()
        guard !prices.isEmpty else { return nil }
        let middle = prices.count / 2
        return prices.count.isMultiple(of: 2) ? (prices[middle - 1] + prices[middle]) / 2 : prices[middle]
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

    /// "4,20 €".
    public static func euros(_ value: Double) -> String {
        "\(frenchDecimal(value, places: 2)) €"
    }

    /// Ligne sous Éco, face à Rapide : temps en plus, km et euros économisés,
    /// "+4 min · −3,2 km · −0,85 €".
    public static func eco(_ eco: Route, against fastest: Route?, fuel: FuelEstimate? = nil) -> String {
        guard let fastest else {
            return fuel.map { "Le plus court · ≈ \(euros($0.cost(meters: eco.distanceMeters)))" } ?? "Le plus court en distance"
        }
        if same(eco, fastest) { return "Même trajet que Rapide" }
        let minutes = roundToInt(Double(eco.expectedSeconds - fastest.expectedSeconds) / 60.0)
        // Temps de sources différentes (HERE muet pour l'un) : écart dit tel quel.
        var parts = [minutes >= 1 ? "+\(minutes) min" : minutes <= -1 ? "−\(-minutes) min" : "Aussi rapide"]
        let saved = fastest.distanceMeters - eco.distanceMeters
        if saved > 0 {
            parts.append("−\(distance(saved))")
            if let fuel, fuel.cost(meters: saved) >= 0.005 { parts.append("−\(euros(fuel.cost(meters: saved)))") }
        }
        return parts.joined(separator: " · ")
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

    /// Ligne sous Rapide, face à Éco : temps gagné, coût estimé, "6 min gagnées · ≈ 4,20 €".
    public static func fastest(_ fastest: Route, against eco: Route?, fuel: FuelEstimate? = nil) -> String {
        var minutes = 0
        if let eco, !same(eco, fastest) {
            minutes = roundToInt(Double(eco.expectedSeconds - fastest.expectedSeconds) / 60.0)
        }
        let gained = minutes >= 1 ? "\(minutes) min gagnée\(minutes > 1 ? "s" : "")" : nil
        guard let fuel else { return gained ?? "Bouchons évités en route" }
        return "\(gained ?? "Bouchons évités") · ≈ \(euros(fuel.cost(meters: fastest.distanceMeters)))"
    }

    /// Ce que traverse la route : "Autoroute · Péage", "Sans autoroute ni péage" ; nil inconnu.
    public static func roads(_ roads: RouteRoads?) -> String? {
        guard let roads else { return nil }
        let parts = [roads.motorway ? "Autoroute" : nil, roads.toll ? "Péage" : nil, roads.ferry ? "Ferry" : nil].compactMap { $0 }
        return parts.isEmpty ? "Sans autoroute ni péage" : parts.joined(separator: " · ")
    }
}
