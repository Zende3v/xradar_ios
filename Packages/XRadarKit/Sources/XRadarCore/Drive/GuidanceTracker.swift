import Foundation

/// Turn-by-turn over one route, as the Android DriveViewModel runs it: a cursor on the maneuver
/// ahead, distances measured along the road (map-matched) rather than as the crow flies, and
/// voice cues where every spoken number is a marker crossed at the moment it is said. A new
/// route (trip or recalculation) starts a new tracker.
public struct GuidanceTracker: Sendable {
    /// A maneuver is behind once the driver is this far past its point: the banner keeps the turn
    /// being made until it is done, instead of already showing the next one.
    static let stepPassedMeters = 12.0
    /// A bend sharper than this at a maneuver tells its real side.
    static let clearBendDeg = 30.0
    static let nearAnnounceMeters = 45
    static let nearAnnounceSeconds = 4.0
    static let farMinMeters = 150.0
    static let farMaxMeters = 1000.0
    /// How long the phrase takes to reach its distance word.
    static let speechLeadSeconds = 2.0
    /// How far ahead the heads-up looks, in seconds of driving.
    static let farLeadSeconds = 14.0
    /// Minimum time left before the final cue for a heads-up to be worth it.
    static let farMinGapSeconds = 7.0
    static let onRouteMeters = 45.0
    /// Round distances the voice may announce, descending.
    static let markers = [1000, 700, 500, 300, 200, 150, 100]

    /// The next maneuver to show, and the phrase to say now (if any).
    public struct Update: Sendable, Hashable {
        public let instruction: GuidanceInstruction?
        public let speech: String?
    }

    public let steps: [RouteStep]
    /// The route as a measurable polyline; nil under two points.
    public let path: RoutePath?
    /// Distance along the route of every maneuver, never decreasing.
    private let stepAlong: [Double]
    private var stepIndex = 1
    private var announcedFar = false
    private var announcedNear = false

    public init(route: Route?) {
        let raw = route?.steps ?? []
        let points = route?.points ?? []
        let path = points.count >= 2 ? RoutePath(points: points) : nil
        let along = Self.alongOfSteps(path, raw)
        self.path = path
        steps = path.map { path in zip(raw, along).map { Self.checkedSide($0, along: $1, path: path) } } ?? raw
        stepAlong = along
    }

    /// The side of a turn as the road itself bends there: when the router's words disagree with a
    /// clear bend the other way, the geometry wins, so the arrow and the voice match the road.
    /// Only real turns: a fork, a ramp or a slight turn is named against the other branch, which
    /// can bend either way.
    static func checkedSide(_ step: RouteStep, along: Double, path: RoutePath) -> RouteStep {
        let turnTypes: Set<String> = ["turn", "new name", "continue", "end of road"]
        let turnModifiers: Set<String> = ["left", "right", "sharp left", "sharp right"]
        guard turnTypes.contains(step.type),
              let modifier = step.modifier, turnModifiers.contains(modifier),
              along > 15, along < path.totalMeters - 15
        else { return step }
        var bend = (path.pose(at: along + 15).bearingDeg - path.pose(at: along - 15).bearingDeg)
            .truncatingRemainder(dividingBy: 360)
        if bend > 180 { bend -= 360 } else if bend < -180 { bend += 360 }
        let saysRight = modifier.contains("right")
        guard abs(bend) >= clearBendDeg, (bend > 0) != saysRight else { return step }
        let fixed = saysRight
            ? modifier.replacingOccurrences(of: "right", with: "left")
            : modifier.replacingOccurrences(of: "left", with: "right")
        return RouteStep(location: step.location, type: step.type, modifier: fixed, name: step.name, distanceMeters: step.distanceMeters, exit: step.exit)
    }

    /// Moves the cursor to the maneuver ahead of [sample] and says what to show and to speak.
    /// With [voice] off nothing is spoken, and nothing is marked as said.
    public mutating func update(sample: LocationSample?, voice: Bool) -> Update {
        guard let sample, steps.count >= 2 else { return Update(instruction: nil, speech: nil) }
        if stepIndex >= steps.count { stepIndex = steps.count - 1 }

        var driverAlong: Double?
        if stepAlong.count == steps.count, let match = path?.match(lat: sample.latitude, lon: sample.longitude),
           match.offRouteMeters <= Self.onRouteMeters {
            driverAlong = match.alongMeters
        }

        if let driverAlong {
            // Exactly how far along the road: a maneuver is behind as soon as its point is passed.
            while stepIndex < steps.count - 1 && driverAlong >= stepAlong[stepIndex] + Self.stepPassedMeters {
                advance()
            }
        } else {
            while stepIndex < steps.count - 1 {
                let current = distance(sample, steps[stepIndex])
                let next = distance(sample, steps[stepIndex + 1])
                guard current < Self.stepPassedMeters || next < current else { break }
                advance()
            }
        }

        let target = steps[stepIndex]
        let meters = driverAlong.map { roundToInt(max(stepAlong[stepIndex] - $0, 0)) } ?? roundToInt(distance(sample, target))
        let road = target.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : target.name
        let instruction = GuidanceInstruction(
            maneuver: GuidanceText.maneuver(of: target),
            distanceMeters: meters,
            primaryText: GuidanceText.verb(target),
            roadName: road
        )

        guard voice else { return Update(instruction: instruction, speech: nil) }
        let speed = max(sample.speedMps ?? 0, 0)
        let secondsAway = speed > 1 ? Double(meters) / speed : .greatestFiniteMagnitude

        // "Maintenant" on time: by distance at low speed, by seconds at high speed.
        if !announcedNear && (meters <= Self.nearAnnounceMeters || secondsAway <= Self.nearAnnounceSeconds) {
            announcedNear = true
            announcedFar = true // never a distance after the final cue
            return Update(instruction: instruction, speech: GuidanceText.spokenNear(target))
        }
        guard !announcedFar else { return Update(instruction: instruction, speech: nil) }
        // Heads-up: a round marker, started early enough that the driver is at that distance
        // when they hear the number.
        let lead = speed * Self.speechLeadSeconds
        let horizon = min(max(speed * Self.farLeadSeconds, Self.farMinMeters), Self.farMaxMeters)
        if let marker = Self.markers.first(where: { Double($0) <= horizon && Double(meters) - lead <= Double($0) }),
           secondsAway > Self.farMinGapSeconds {
            announcedFar = true
            return Update(instruction: instruction, speech: GuidanceText.spokenFar(target, meters: marker))
        }
        return Update(instruction: instruction, speech: nil)
    }

    private mutating func advance() {
        stepIndex += 1
        announcedFar = false
        announcedNear = false
    }

    private func distance(_ sample: LocationSample, _ step: RouteStep) -> Double {
        Geo.haversine(lat1: sample.latitude, lon1: sample.longitude, lat2: step.location.lat, lon2: step.location.lon)
    }

    private static func alongOfSteps(_ path: RoutePath?, _ steps: [RouteStep]) -> [Double] {
        guard let path, !steps.isEmpty else { return [] }
        var last = 0.0
        return steps.map { step in
            let along = max(path.match(lat: step.location.lat, lon: step.location.lon)?.alongMeters ?? last, last)
            last = along
            return along
        }
    }
}
