/// Permis probatoire (code de la route, art. R413-5) : 110 km/h au lieu de 130 sur autoroute,
/// 100 au lieu de 110 sur voie rapide, 80 au lieu de 90 hors agglomération. Autres limites
/// inchangées. Limitation officielle gardée à part : signalements, sondes, caméra.
public enum ProbationaryLimits {
    public static func adjusted(_ kmh: Int) -> Int {
        switch kmh {
        case 130: 110
        case 110: 100
        case 90: 80
        default: kmh
        }
    }

    public static func adjusted(_ kmh: Int?, probationary: Bool) -> Int? {
        guard probationary, let kmh else { return kmh }
        return adjusted(kmh)
    }

    /// Limite affichée : permis probatoire, puis plafond du véhicule ([capKmh], 45 pour scooter 50
    /// et sans permis). Limite inconnue : inconnue.
    public static func shown(_ kmh: Int?, probationary: Bool, capKmh: Int?) -> Int? {
        guard let limit = adjusted(kmh, probationary: probationary) else { return nil }
        return capKmh.map { min(limit, $0) } ?? limit
    }
}

public extension RoadAlert {
    /// Même alerte, autre limitation affichée.
    func with(speedLimitKmh limit: Int?) -> RoadAlert {
        RoadAlert(
            type: type, title: title, roadLabel: roadLabel, speedLimitKmh: limit, distanceMeters: distanceMeters,
            etaSeconds: etaSeconds, confidence: confidence, lastReportedLabel: lastReportedLabel, id: id
        )
    }
}
