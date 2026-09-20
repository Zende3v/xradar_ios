/// A computed driving route: the polyline to draw, distance, duration and steps.
public struct Route: Sendable, Hashable {
    public let points: [GeoPoint]
    public let distanceMeters: Int
    public let durationSeconds: Int
    public let steps: [RouteStep]

    public init(points: [GeoPoint], distanceMeters: Int, durationSeconds: Int, steps: [RouteStep] = []) {
        self.points = points
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.steps = steps
    }
}

/// One turn-by-turn step from OSRM. [location] is where the maneuver happens (the turn point);
/// [name] is the road followed after it. Distances in metres.
public struct RouteStep: Sendable, Hashable {
    public let location: GeoPoint
    public let type: String
    public let modifier: String?
    public let name: String
    public let distanceMeters: Int
    public let exit: Int?

    public init(location: GeoPoint, type: String, modifier: String?, name: String, distanceMeters: Int, exit: Int?) {
        self.location = location
        self.type = type
        self.modifier = modifier
        self.name = name
        self.distanceMeters = distanceMeters
        self.exit = exit
    }
}

/// Pre-formatted trip summary shown on the HUD.
public struct TripInfo: Sendable, Hashable {
    public let remainingLabel: String
    public let distanceLabel: String
    public let arrivalLabel: String

    public init(remainingLabel: String, distanceLabel: String, arrivalLabel: String) {
        self.remainingLabel = remainingLabel
        self.distanceLabel = distanceLabel
        self.arrivalLabel = arrivalLabel
    }
}

/// Visual class of a maneuver: selects the arrow shown on the guidance banner.
public enum Maneuver: Sendable, Hashable, CaseIterable {
    case depart
    case straight
    case slightLeft
    case slightRight
    case left
    case right
    case sharpLeft
    case sharpRight
    case uturn
    case roundabout
    case merge
    case ramp
    case forkLeft
    case forkRight
    case arrive
}

/// The next maneuver to display (and announce) while navigating.
public struct GuidanceInstruction: Sendable, Hashable {
    public let maneuver: Maneuver
    public let distanceMeters: Int
    /// e.g. "Tournez à droite".
    public let primaryText: String
    /// Road turned onto, e.g. "Rue de la Paix" (nil when unnamed).
    public let roadName: String?

    public init(maneuver: Maneuver, distanceMeters: Int, primaryText: String, roadName: String?) {
        self.maneuver = maneuver
        self.distanceMeters = distanceMeters
        self.primaryText = primaryText
        self.roadName = roadName
    }
}
