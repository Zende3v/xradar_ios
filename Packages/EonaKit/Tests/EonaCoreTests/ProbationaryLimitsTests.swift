import Testing
@testable import EonaCore

struct ProbationaryLimitsTests {
    @Test func youngDriverLimits() {
        #expect(ProbationaryLimits.adjusted(130) == 110)
        #expect(ProbationaryLimits.adjusted(110) == 100)
        #expect(ProbationaryLimits.adjusted(90) == 80)
        for kmh in [30, 50, 70, 80, 100] {
            #expect(ProbationaryLimits.adjusted(kmh) == kmh)
        }
        #expect(ProbationaryLimits.adjusted(130, probationary: false) == 130)
        #expect(ProbationaryLimits.adjusted(nil, probationary: true) == nil)
    }

    @Test func mopedCapAfterYoungDriver() {
        #expect(ProbationaryLimits.shown(90, probationary: false, capKmh: 45) == 45)
        #expect(ProbationaryLimits.shown(30, probationary: true, capKmh: 45) == 30)
        #expect(ProbationaryLimits.shown(130, probationary: true, capKmh: nil) == 110)
        #expect(ProbationaryLimits.shown(nil, probationary: true, capKmh: 45) == nil)
    }

    @Test func alertKeepsEverythingButItsLimit() {
        let alert = RoadAlert(type: .radarFixed, title: "Radar fixe", roadLabel: nil, speedLimitKmh: 130, distanceMeters: 250,
                              etaSeconds: 7, confidence: 1, lastReportedLabel: nil, id: "r1")
        let young = alert.with(speedLimitKmh: 110)
        #expect(young.speedLimitKmh == 110)
        #expect(young.key == alert.key)
        #expect(young.distanceMeters == 250)
    }
}
