import Foundation
import Testing
@testable import XRadarCore

struct GeoTests {
    @Test func haversineParisLyon() {
        let meters = Geo.haversine(lat1: 48.8566, lon1: 2.3522, lat2: 45.7640, lon2: 4.8357)
        #expect(abs(meters - 391_500) < 3_000)
    }

    @Test func bearingsFollowTheCompass() {
        #expect(abs(Geo.bearing(lat1: 0, lon1: 0, lat2: 1, lon2: 0)) < 1e-9)
        #expect(abs(Geo.bearing(lat1: 0, lon1: 0, lat2: 0, lon2: 1) - 90) < 1e-9)
        #expect(abs(Geo.bearing(lat1: 1, lon1: 0, lat2: 0, lon2: 0) - 180) < 1e-9)
    }

    @Test func angularDiffWrapsAtNorth() {
        #expect(Geo.angularDiff(350, 10) == 20)
        #expect(Geo.angularDiff(10, 350) == 20)
        #expect(Geo.angularDiff(0, 180) == 180)
    }
}

struct RoutePathTests {
    let line = RoutePath(points: [GeoPoint(lat: 0, lon: 0), GeoPoint(lat: 0, lon: 0.01), GeoPoint(lat: 0, lon: 0.02)])

    @Test func measuresTheLine() {
        #expect(abs(line.totalMeters - 2223.9) < 1)
    }

    @Test func snapsAFixOntoTheLine() throws {
        let match = try #require(line.match(lat: 0.0001, lon: 0.005))
        #expect(abs(match.alongMeters - 555.97) < 0.5)
        #expect(abs(match.offRouteMeters - 11.12) < 0.1)
        #expect(abs(match.bearingDeg - 90) < 1e-6)
        #expect(abs(match.lon - 0.005) < 1e-9)
        #expect(abs(match.lat) < 1e-12)
    }

    @Test func readsThePoseAndClamps() {
        #expect(abs(line.pose(at: line.totalMeters / 2).point.lon - 0.01) < 1e-9)
        #expect(line.pose(at: -5).point.lon == 0)
        #expect(abs(line.pose(at: 99_999).point.lon - 0.02) < 1e-12)
    }

    @Test func trimsTheDrivenPart() {
        let ahead = line.trimmed(from: line.totalMeters * 0.75)
        #expect(ahead.count == 2)
        #expect(abs(ahead[0].lon - 0.015) < 1e-6)
        #expect(ahead[1] == GeoPoint(lat: 0, lon: 0.02))
    }

    @Test func needsTwoPoints() {
        #expect(RoutePath(points: [GeoPoint(lat: 1, lon: 1)]).match(lat: 1, lon: 1) == nil)
        #expect(RoutePath(points: []).totalMeters == 0)
    }
}

struct SunClockTests {
    @Test func summerAfternoonInParisIsDay() {
        let noon = Date(millis: parisMillis(2026, 6, 21, 14, 0))
        #expect(SunClock.isDaylight(lat: 48.8566, lon: 2.3522, at: noon))
        #expect(SunClock.altitudeDeg(lat: 48.8566, lon: 2.3522, at: noon) > 55)
    }

    @Test func nightsAreNight() {
        #expect(!SunClock.isDaylight(lat: 48.8566, lon: 2.3522, at: Date(millis: parisMillis(2026, 6, 21, 1, 30))))
        #expect(!SunClock.isDaylight(lat: 48.8566, lon: 2.3522, at: Date(millis: parisMillis(2026, 12, 21, 18, 30))))
        #expect(SunClock.isDaylight(lat: 48.8566, lon: 2.3522, at: Date(millis: parisMillis(2026, 12, 21, 13, 0))))
    }
}

struct GuidanceTextTests {
    @Test func picksTheArrow() {
        #expect(GuidanceText.maneuver(of: step("turn", "right")) == .right)
        #expect(GuidanceText.maneuver(of: step("fork", "slight left")) == .forkLeft)
        #expect(GuidanceText.maneuver(of: step("rotary")) == .roundabout)
        #expect(GuidanceText.maneuver(of: step("off ramp", "right")) == .ramp)
        #expect(GuidanceText.maneuver(of: step("off ramp", "slight left")) == .slightLeft)
        #expect(GuidanceText.maneuver(of: step("new name")) == .straight)
    }

    @Test func phrasesTheManeuver() {
        #expect(GuidanceText.verb(step("roundabout", exit: 1)) == "Au rond-point, prenez la 1re sortie")
        #expect(GuidanceText.verb(step("roundabout", exit: 3)) == "Au rond-point, prenez la 3e sortie")
        #expect(GuidanceText.verb(step("roundabout")) == "Prenez le rond-point")
        #expect(GuidanceText.verb(step("off ramp", "slight right")) == "Prenez la sortie à droite")
        #expect(GuidanceText.verb(step("end of road", "left")) == "Au bout de la route, à gauche")
        #expect(GuidanceText.verb(step("continue", "uturn")) == "Faites demi-tour")
        #expect(GuidanceText.verb(step("continue")) == "Continuez tout droit")
        #expect(GuidanceText.verb(step("turn", "sharp left")) == "Tournez franchement à gauche")
    }

    @Test func labelsDistances() {
        #expect(GuidanceText.distanceLabel(15) == "15 m")
        #expect(GuidanceText.distanceLabel(234) == "230 m")
        #expect(GuidanceText.distanceLabel(235) == "240 m")
        #expect(GuidanceText.distanceLabel(1234) == "1,2 km")
        #expect(GuidanceText.distanceLabel(1260) == "1,3 km")
        #expect(GuidanceText.distanceLabel(15_400) == "15 km")
    }

    @Test func speaksDistances() {
        #expect(GuidanceText.spokenDistance(10) == "50 mètres")
        #expect(GuidanceText.spokenDistance(120) == "100 mètres")
        #expect(GuidanceText.spokenDistance(130) == "150 mètres")
        #expect(GuidanceText.spokenDistance(1000) == "1 kilomètre")
        #expect(GuidanceText.spokenDistance(2000) == "2 kilomètres")
        #expect(GuidanceText.spokenDistance(1500) == "1,5 kilomètre")
        #expect(GuidanceText.spokenDistance(2500) == "2,5 kilomètres")
        #expect(GuidanceText.spokenDistance(12_000) == "12 kilomètres")
    }

    @Test func speaksInstructions() {
        #expect(GuidanceText.spokenFar(step("turn", "right", name: "Rue de la Paix"), meters: 300)
            == "Dans 300 mètres, tournez à droite sur Rue de la Paix")
        #expect(GuidanceText.spokenFar(step("roundabout", name: "Avenue", exit: 2), meters: 300)
            == "Dans 300 mètres, au rond-point, prenez la 2e sortie")
        #expect(GuidanceText.spokenFar(step("arrive"), meters: 300) == "Vous êtes bientôt arrivé")
        #expect(GuidanceText.spokenNear(step("turn", "right")) == "Tournez à droite maintenant")
        #expect(GuidanceText.spokenNear(step("continue")) == "Continuez tout droit")
        #expect(GuidanceText.spokenNear(step("fork", "left")) == "Restez à gauche")
        #expect(GuidanceText.spokenNear(step("arrive")) == "Vous êtes arrivé à destination")
    }
}
