import Foundation
import Testing
@testable import EonaCore

/// A fix on the equator heading east, at [kmh].
private func fix(lon: Double, lat: Double = 0, bearing: Double? = 90, kmh: Double = 36) -> LocationSample {
    LocationSample(latitude: lat, longitude: lon, speedMps: kmh / 3.6, bearingDeg: bearing, accuracyM: 5, timeMs: 0)
}

private func alert(_ id: String, meters: Int, title: String = "Radar fixe", vma: Int? = nil, road: String? = nil) -> RoadAlert {
    RoadAlert(type: .radarFixed, title: title, roadLabel: road, speedLimitKmh: vma, distanceMeters: meters, etaSeconds: 0, confidence: 1, lastReportedLabel: nil, id: id)
}

struct AlertsAheadTests {
    let radars = [
        Radar(id: "speed", code: "ETF", vma: 90, lat: 0, lon: 0.005),
        Radar(id: "red", code: "ETFR", vma: nil, lat: 0, lon: 0.002),
        Radar(id: "behind", code: "ETF", vma: 50, lat: 0, lon: -0.003),
        Radar(id: "far", code: "ETF", vma: 110, lat: 0, lon: 0.008),
    ]

    @Test func radarsAheadNearestFirstWithTheLimit() {
        let result = AlertsAhead.radars(radars, sample: fix(lon: 0), speedKmh: 36)
        #expect(result.alerts.map(\.id) == ["red", "speed"])
        #expect(result.alerts.map(\.distanceMeters) == [222, 556])
        #expect(result.alerts.map(\.etaSeconds) == [22, 56])
        #expect(result.alerts[0].title == "Radar feu rouge")
        #expect(result.limitKmh == 90)
    }

    @Test func withoutACourseEverythingIsAhead() {
        let result = AlertsAhead.radars(radars, sample: fix(lon: 0, bearing: nil), speedKmh: 0)
        #expect(result.alerts.map(\.id) == ["red", "behind", "speed"])
        #expect(result.alerts[1].etaSeconds == 334)
    }

    @Test func reportsNeedTheScoreAndTheDistance() {
        let ahead = UserReport(id: "ahead", type: .accident, lat: 0, lon: 0.003, ageMillis: 0, reporters: 2, bearingDeg: 90, score: 80)
        let opposite = UserReport(id: "opposite", type: .accident, lat: 0, lon: 0.003, ageMillis: 0, direction: "opposite", bearingDeg: 90, score: 80)
        let tooFar = UserReport(id: "far", type: .accident, lat: 0, lon: 0.007, ageMillis: 0, bearingDeg: 90, score: 80)
        let camera = UserReport(id: "camera", type: .camera, lat: 0, lon: 0.001, ageMillis: 0, bearingDeg: 90, score: 100, side: "left")
        let alerts = AlertsAhead.reports([ahead, opposite, tooFar, camera], sample: fix(lon: 0), speedKmh: 36) { _ in true }
        #expect(alerts.map(\.id) == ["camera", "ahead"])
        #expect(alerts[0].roadLabel == "côté à gauche")
        #expect(alerts[1].roadLabel == nil)
        #expect(alerts[1].lastReportedLabel == "2 signalements · à l'instant")
        #expect(abs(alerts[1].confidence - 0.622) < 0.001)
    }

    @Test func voiceBands() {
        #expect(AlertsAhead.announcement(for: alert("a", meters: 450, vma: 90))?.text == "Radar fixe dans 450 mètres, vitesse 90.")
        #expect(AlertsAhead.announcement(for: alert("a", meters: 450))?.band == 500)
        let near = AlertsAhead.announcement(for: alert("a", meters: 150, road: "Sens opposé"))
        #expect(near?.band == 200)
        #expect(near?.text == "Radar fixe, Sens opposé.")
        #expect(AlertsAhead.announcement(for: alert("a", meters: 650)) == nil)
    }

    @Test func labelsAndKeys() {
        #expect(RoadAlert.distanceLabel(650) == "650 m")
        #expect(RoadAlert.distanceLabel(1250) == "1,3 km")
        #expect(alert("r1", meters: 1, vma: 90, road: "Sens opposé").subtitle == "Sens opposé · limité à 90 km/h")
        #expect(alert("r1", meters: 1).subtitle.isEmpty)
        #expect(alert("r1", meters: 1).key == "r1")
    }

    @Test func closeNeighboursKeepTheirOrder() {
        let a = alert("a", meters: 100)
        #expect(RoadAlert.stableOrder(previous: ["b", "a"], alerts: [a, alert("b", meters: 120)], marginMeters: 30).map(\.id) == ["b", "a"])
        #expect(RoadAlert.stableOrder(previous: ["b", "a"], alerts: [a, alert("b", meters: 140)], marginMeters: 30).map(\.id) == ["a", "b"])
        #expect(RoadAlert.stableOrder(previous: [], alerts: [alert("b", meters: 120), a], marginMeters: 30).map(\.id) == ["a", "b"])
    }
}

struct SpeedFilterTests {
    @Test func noiseAtAStopReadsZero() {
        var filter = SpeedFilter()
        #expect(filter.update(speed: 0.3, accuracy: 0.5, timeMs: 0) == 0)
        #expect(filter.update(speed: 1.6, accuracy: 3.0, timeMs: 1000) == 0)
        #expect(filter.update(speed: 2.2, accuracy: 0.6, timeMs: 2000) == 0)
        #expect(filter.update(speed: 0.4, accuracy: 0.5, timeMs: 3000) == 0)
        #expect(filter.update(speed: -1, accuracy: -1, timeMs: 4000) == 0)
    }

    @Test func startsClampsSpikesAndStops() {
        var filter = SpeedFilter()
        #expect(filter.update(speed: 3, accuracy: 0.5, timeMs: 0) == 0)
        #expect(filter.update(speed: 3, accuracy: 0.5, timeMs: 1000) > 0)
        var speed = 0.0
        for second in 2...21 {
            speed = filter.update(speed: 20, accuracy: 0.5, timeMs: second * 1000)
        }
        #expect(abs(speed - 20) < 0.5)
        // A 40 m/s spike in one second is no car: clamped.
        #expect(filter.update(speed: 40, accuracy: 0.5, timeMs: 22_000) < 24.1)
        // A sudden 0 at speed is a glitch; the car stops only once it is really slow.
        #expect(filter.update(speed: 0.5, accuracy: 0.5, timeMs: 23_000) > 5)
        for second in 24...28 {
            speed = filter.update(speed: 0.5, accuracy: 0.5, timeMs: second * 1000)
        }
        #expect(speed == 0)
    }
}

struct AlertBeepsTests {
    @Test func fasterAsTheRadarNears() {
        #expect(AlertBeeps.interval(meters: 701) == nil)
        #expect(AlertBeeps.interval(meters: 700) == 2.0)
        #expect(AlertBeeps.interval(meters: 450) == 1.3)
        #expect(AlertBeeps.interval(meters: 300) == 0.8)
        #expect(AlertBeeps.interval(meters: 150) == 0.45)
        #expect(AlertBeeps.interval(meters: 61) == 0.45)
        #expect(AlertBeeps.interval(meters: 60) == nil)
        #expect(AlertType.radarCar.isEnforcement)
        #expect(!AlertType.accident.isEnforcement)
        #expect(!ReportType.trafficJam.raisesAlerts)
    }
}

struct RouteCorridorTests {
    let corridor = RouteCorridor(route: (0...100).map { GeoPoint(lat: 0, lon: Double($0) * 0.01) })

    @Test func keepsWhatIsNearTheRouteOrTheDriver() {
        #expect(corridor.contains(lat: 0.1, lon: 0.5, driverLat: 0, driverLon: 0))
        #expect(!corridor.contains(lat: 0.2, lon: 0.5, driverLat: 0, driverLon: 0))
        #expect(corridor.contains(lat: 0.2, lon: 0.5, driverLat: 0.1, driverLon: 0.5))
        #expect(!RouteCorridor(route: []).contains(lat: 0.1, lon: 0.5, driverLat: 0, driverLon: 0))
    }
}

struct GuidanceTrackerTests {
    let route = Route(
        points: [GeoPoint(lat: 0, lon: 0), GeoPoint(lat: 0, lon: 0.01), GeoPoint(lat: 0, lon: 0.02)],
        distanceMeters: 2224,
        durationSeconds: 222,
        steps: [
            RouteStep(location: GeoPoint(lat: 0, lon: 0), type: "depart", modifier: nil, name: "", distanceMeters: 1112, exit: nil),
            RouteStep(location: GeoPoint(lat: 0, lon: 0.01), type: "turn", modifier: "right", name: "Rue A", distanceMeters: 1112, exit: nil),
            RouteStep(location: GeoPoint(lat: 0, lon: 0.02), type: "arrive", modifier: nil, name: "", distanceMeters: 0, exit: nil),
        ]
    )

    @Test func showsTheManeuverAheadAlongTheRoad() throws {
        var tracker = GuidanceTracker(route: route)
        let update = tracker.update(sample: fix(lon: 0.001), voice: true)
        let instruction = try #require(update.instruction)
        // 1111.95 m to the turn, minus the 111.2 m driven.
        #expect(instruction.maneuver == .right)
        #expect(instruction.distanceMeters == 1001)
        #expect(instruction.primaryText == "Tournez à droite")
        #expect(instruction.roadName == "Rue A")
        #expect(update.speech == nil)
    }

    @Test func speaksTheMarkerThenTheFinalCueOnce() {
        var tracker = GuidanceTracker(route: route)
        let far = tracker.update(sample: fix(lon: 0.0088), voice: true)
        let farAgain = tracker.update(sample: fix(lon: 0.0089), voice: true)
        let near = tracker.update(sample: fix(lon: 0.0097), voice: true)
        let turning = tracker.update(sample: fix(lon: 0.0100), voice: true)
        let past = tracker.update(sample: fix(lon: 0.0102), voice: true)
        #expect(far.speech == "Dans 150 mètres, tournez à droite sur Rue A")
        #expect(farAgain.speech == nil)
        #expect(near.speech == "Tournez à droite maintenant")
        // At the turn itself the banner still shows it, not the next maneuver.
        #expect(turning.instruction?.maneuver == .right)
        #expect(past.speech == nil)
        #expect(past.instruction?.maneuver == .arrive)
    }

    @Test func theRoadDecidesTheSideOfATurn() {
        let bend = Route(
            points: [GeoPoint(lat: 0, lon: 0), GeoPoint(lat: 0, lon: 0.01), GeoPoint(lat: 0.01, lon: 0.01)],
            distanceMeters: 2224,
            durationSeconds: 222,
            steps: [
                RouteStep(location: GeoPoint(lat: 0, lon: 0), type: "depart", modifier: nil, name: "", distanceMeters: 1112, exit: nil),
                RouteStep(location: GeoPoint(lat: 0, lon: 0.01), type: "turn", modifier: "right", name: "", distanceMeters: 1112, exit: nil),
                RouteStep(location: GeoPoint(lat: 0.01, lon: 0.01), type: "arrive", modifier: nil, name: "", distanceMeters: 0, exit: nil),
            ]
        )
        // Eastward then north is a left turn, whatever the router said.
        #expect(GuidanceTracker(route: bend).steps[1].modifier == "left")
        // No bend on a straight line: the router's side stays.
        #expect(GuidanceTracker(route: route).steps[1].modifier == "right")
    }

    @Test func passesTheTurnAndStaysSilentWithoutVoice() {
        var tracker = GuidanceTracker(route: route)
        let update = tracker.update(sample: fix(lon: 0.0102), voice: false)
        let lost = tracker.update(sample: nil, voice: true)
        var none = GuidanceTracker(route: nil)
        let noRoute = none.update(sample: fix(lon: 0), voice: true)
        #expect(update.instruction?.maneuver == .arrive)
        #expect(update.speech == nil)
        #expect(lost.instruction == nil)
        #expect(noRoute.instruction == nil)
    }
}

struct TripProgressTests {
    @Test func formatsTheDockFigures() {
        let now = Date(timeIntervalSince1970: Double(parisMillis(2026, 9, 14, 19, 0)) / 1000)
        let long = TripInfo.of(Route(points: [], distanceMeters: 12_345, durationSeconds: 3_725), now: now, timeZone: paris)
        #expect(long == TripInfo(remainingLabel: "1 h 02", distanceLabel: "12 km", arrivalLabel: "20:02"))
        let short = TripInfo.of(Route(points: [], distanceMeters: 4_250, durationSeconds: 540), now: now, timeZone: paris)
        #expect(short == TripInfo(remainingLabel: "9 min", distanceLabel: "4,3 km", arrivalLabel: "19:09"))
    }

    @Test func shrinksWithTheRouteLeft() {
        let now = Date(timeIntervalSince1970: Double(parisMillis(2026, 9, 14, 8, 0)) / 1000)
        let route = Route(points: [], distanceMeters: 2_600, durationSeconds: 360)
        // 450 m left of 2,6 km: about a minute, not the whole trip.
        let near = TripInfo.of(route, remainingShare: 450.0 / 2_600, now: now, timeZone: paris)
        #expect(near == TripInfo(remainingLabel: "1 min", distanceLabel: "450 m", arrivalLabel: "08:01"))
        let half = TripInfo.of(route, remainingShare: 0.5, now: now, timeZone: paris)
        #expect(half == TripInfo(remainingLabel: "3 min", distanceLabel: "1,3 km", arrivalLabel: "08:03"))
        // Out of range, the share is held within the route.
        let before = TripInfo.of(route, remainingShare: 1.4, now: now, timeZone: paris)
        #expect(before == TripInfo(remainingLabel: "6 min", distanceLabel: "2,6 km", arrivalLabel: "08:06"))
        let there = TripInfo.of(route, remainingShare: 0, now: now, timeZone: paris)
        #expect(there == TripInfo(remainingLabel: "0 min", distanceLabel: "0 m", arrivalLabel: "08:00"))
    }

    @Test func distanceLabelsRound() {
        #expect(TripInfo.distanceLabel(meters: 994) == "990 m")
        #expect(TripInfo.distanceLabel(meters: 996) == "1,0 km")
        #expect(TripInfo.distanceLabel(meters: 12_400) == "12 km")
    }
}
