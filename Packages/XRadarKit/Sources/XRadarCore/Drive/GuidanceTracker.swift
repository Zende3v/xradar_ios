import Foundation

/// Turn-by-turn over one route, as the Android DriveViewModel runs it: a cursor on the maneuver
/// ahead, distances measured along the road (map-matched) rather than as the crow flies, and
/// voice cues where every spoken number is a marker crossed at the moment it is said. A new
/// route (trip or recalculation) starts a new tracker.
public struct GuidanceTracker: Sendable {
    static let stepReachedMeters = 25.0
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
        let steps = route?.steps ?? []
        let points = route?.points ?? []
        let path = points.count >= 2 ? RoutePath(points: points) : nil
        self.steps = steps
        self.path = path
        stepAlong = Self.alongOfSteps(path, steps)
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
            while stepIndex < steps.count - 1 && driverAlong >= stepAlong[stepIndex] - Self.stepReachedMeters {
                advance()
            }
        } else {
            while stepIndex < steps.count - 1 {
                let current = distance(sample, steps[stepIndex])
                let next = distance(sample, steps[stepIndex + 1])
                guard current < Self.stepReachedMeters || next < current else { break }
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
