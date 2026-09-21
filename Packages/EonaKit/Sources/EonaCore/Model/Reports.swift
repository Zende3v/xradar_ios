/// A crowdsourced report category; the raw value is exchanged with the backend.
/// How bad an "Embouteillage" is, as the driver sees it. It decides what the jam costs when
/// the routing looks for a way round: a standstill is worth going round, a light one is not.
public enum JamSeverity: String, Sendable, Hashable, CaseIterable {
    case light
    case heavy
    case standstill

    public var label: String {
        switch self {
        case .light: "Léger"
        case .heavy: "Important"
        case .standstill: "À l'arrêt"
        }
    }
}

public enum ReportType: String, Sendable, Hashable, CaseIterable {
    case voitureRadar = "voiture_radar"
    case camera
    case hazard
    case radarMobile = "radar_mobile"
    case controlZone = "control_zone"
    case stoppedVehicle = "stopped_vehicle"
    case accident
    case objectOnRoad = "object_on_road"
    case trafficJam = "traffic_jam"
    case damagedRoad = "damaged_road"
    case roadworks
    case slipperyRoad = "slippery_road"
    case lowVisibility = "low_visibility"
    case roadCrew = "road_crew"
    case wrongWay = "wrong_way"

    public var label: String {
        switch self {
        case .voitureRadar: "Voiture radar"
        case .camera: "Caméra"
        case .hazard: "Danger"
        case .radarMobile: "Radar mobile"
        case .controlZone: "Zone de contrôle"
        case .stoppedVehicle: "Véhicule arrêté"
        case .accident: "Accident"
        case .objectOnRoad: "Objet sur la voie"
        case .trafficJam: "Embouteillage"
        case .damagedRoad: "Chaussée dégradée"
        case .roadworks: "Travaux"
        case .slipperyRoad: "Route glissante"
        case .lowVisibility: "Visibilité réduite"
        case .roadCrew: "Personnel autoroutier"
        case .wrongWay: "Véhicule à contresens"
        }
    }

    /// The visual vocabulary it reuses.
    public var alertType: AlertType {
        switch self {
        case .voitureRadar: .radarCar
        case .camera: .camera
        case .radarMobile: .radarMobile
        case .controlZone: .controlZone
        case .accident: .accident
        case .roadworks, .roadCrew: .roadwork
        case .hazard, .stoppedVehicle, .objectOnRoad, .trafficJam, .damagedRoad, .slipperyRoad, .lowVisibility, .wrongWay:
            .hazard
        }
    }

    /// Who may create it.
    public var minRole: Role {
        switch self {
        case .voitureRadar: .client
        case .camera: .admin
        default: .guest
        }
    }

    /// The report sheet must collect a street.
    public var needsStreet: Bool {
        false
    }

    /// The report sheet must collect a plate.
    public var needsPlate: Bool {
        self == .voitureRadar
    }

    /// Can an account with [role] create this report type?
    public func allowed(for role: Role) -> Bool {
        role >= minRole
    }

    /// What the report sheet offers, in the order it is shown (6 per page).
    public static let picker: [ReportType] = [
        .radarMobile,
        .controlZone,
        .voitureRadar,
        .stoppedVehicle,
        .accident,
        .objectOnRoad,
        .trafficJam,
        .damagedRoad,
        .roadworks,
        .slipperyRoad,
        .lowVisibility,
        .roadCrew,
        .wrongWay,
        // Admin only, so it lands at the end of the last page.
        .camera,
    ]
}

/// A crowdsourced report as seen by the app. The age label and confidence derive from the
/// backend's counters.
public struct UserReport: Sendable, Hashable {
    public let id: String
    public let type: ReportType
    public let lat: Double
    public let lon: Double
    /// Milliseconds since the report was created (from the backend).
    public let ageMillis: Int
    /// Confirmations and contradictions the crowd has posted.
    public let confirmations: Int
    public let contradictions: Int
    /// How many people reported it (the first one, plus every confirmation).
    public let reporters: Int
    /// "same" = the driver's own carriageway, "opposite" = the other one.
    public let direction: String
    /// Course of the reporter, in degrees: orients a control zone on the map.
    public let bearingDeg: Double?
    /// Relevance right now (0...100), decayed by the backend since the last report.
    public let score: Int
    /// How far ahead this type is worth warning about, in metres.
    public let impactMeters: Double
    /// A fixed camera: it never decays and only an admin removes it.
    public let persistent: Bool
    /// "guest" / "client" / "admin": informational; guests and members count alike.
    public let reporterRole: String
    /// Camera reports: the precise street and side ("left"/"right").
    public let street: String?
    public let side: String?

    public init(
        id: String,
        type: ReportType,
        lat: Double,
        lon: Double,
        ageMillis: Int,
        confirmations: Int = 0,
        contradictions: Int = 0,
        reporters: Int = 1,
        direction: String = "same",
        bearingDeg: Double? = nil,
        score: Int = 0,
        impactMeters: Double = 1500,
        persistent: Bool = false,
        reporterRole: String = "guest",
        street: String? = nil,
        side: String? = nil
    ) {
        self.id = id
        self.type = type
        self.lat = lat
        self.lon = lon
        self.ageMillis = ageMillis
        self.confirmations = confirmations
        self.contradictions = contradictions
        self.reporters = reporters
        self.direction = direction
        self.bearingDeg = bearingDeg
        self.score = score
        self.impactMeters = impactMeters
        self.persistent = persistent
        self.reporterRole = reporterRole
        self.street = street
        self.side = side
    }

    /// "Mon sens" / "Sens opposé".
    public var directionLabel: String {
        direction == "opposite" ? "Sens opposé" : "Mon sens"
    }

    /// "3 signalements · il y a 12 min": who saw it, and how fresh that is.
    public var crowdLabel: String {
        (reporters > 1 ? "\(reporters) signalements" : "1 signalement") + " · " + ageLabel
    }

    /// "à gauche" / "à droite" / nil.
    public var sideLabel: String? {
        switch side {
        case "left"?: "à gauche"
        case "right"?: "à droite"
        default: nil
        }
    }

    /// The intrinsic score as a 0...1 gauge, for the reliability bar.
    public var confidence: Double {
        min(max(Double(score) / 100.0, 0), 1)
    }

    /// "à l'instant", "il y a 5 min", "il y a 2 h".
    public var ageLabel: String {
        let minutes = ageMillis / 60_000
        if minutes < 1 { return "à l'instant" }
        if minutes < 60 { return "il y a \(minutes) min" }
        return "il y a \(minutes / 60) h"
    }
}

/// How much a report is worth to this driver, right now.
public enum Relevance: Sendable, Hashable {
    case gone
    case low
    case normal
    case high
}

/// The driver-facing half of the report score. The backend keeps the intrinsic part (time
/// decay, confirmations, contradictions); this multiplies it by what depends on who asks:
///
///     final = intrinsic × road × direction × distance
public enum ReportRelevance {

    public static let minimum = 10.0
    static let low = 10.0
    static let normal = 30.0
    static let high = 60.0

    static let roadSame = 1.0
    static let roadOther = 0.35
    static let directionSame = 1.0
    static let directionUnknown = 0.75
    static let directionOpposite = 0.15

    /// Beyond this angle the two courses are opposite; under it, the same way.
    static let sameWayDeg = 60.0
    static let oppositeWayDeg = 120.0

    /// [distanceMeters] from the driver, [driverBearing] their course (nil = unknown),
    /// [onSameRoad] false when the report sits off the road being driven.
    public static func score(
        _ report: UserReport,
        distanceMeters: Double,
        driverBearing: Double?,
        onSameRoad: Bool = true
    ) -> Double {
        let distance = max(0.0, 1.0 - distanceMeters / report.impactMeters)
        if distance <= 0 { return 0 }
        let road = onSameRoad ? roadSame : roadOther
        return Double(report.score) * road * directionFactor(report, driverBearing: driverBearing) * distance
    }

    /// The carriageway the report is on, compared with where the driver is heading. The
    /// reporter's course plus their answer ("mon sens" / "sens opposé") gives the absolute
    /// direction of the event; without a course, nobody can tell.
    public static func directionFactor(_ report: UserReport, driverBearing: Double?) -> Double {
        guard let reported = report.bearingDeg, let driver = driverBearing else { return directionUnknown }
        let eventWay = report.direction == "opposite" ? reported + 180.0 : reported
        let delta = angleBetween(eventWay, driver)
        if delta <= sameWayDeg { return directionSame }
        if delta >= oppositeWayDeg { return directionOpposite }
        return directionUnknown
    }

    /// Band the app shows: under the minimum the backend has already dropped it.
    public static func band(of score: Double) -> Relevance {
        if score < low { return .gone }
        if score < normal { return .low }
        if score < high { return .normal }
        return .high
    }

    public static func label(_ band: Relevance) -> String {
        switch band {
        case .gone: "Périmé"
        case .low: "Pertinence faible"
        case .normal: "Pertinence normale"
        case .high: "Forte pertinence"
        }
    }

    /// Smallest angle between two courses, in degrees (0...180).
    private static func angleBetween(_ a: Double, _ b: Double) -> Double {
        let d = abs((a - b).truncatingRemainder(dividingBy: 360.0))
        return d > 180.0 ? 360.0 - d : d
    }
}
