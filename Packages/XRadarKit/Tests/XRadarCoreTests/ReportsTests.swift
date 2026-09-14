import Testing
@testable import XRadarCore

struct ReportRelevanceTests {
    func report(score: Int = 80, bearing: Double? = 90, direction: String = "same") -> UserReport {
        UserReport(id: "r", type: .accident, lat: 0, lon: 0, ageMillis: 0, direction: direction, bearingDeg: bearing, score: score, impactMeters: 1000)
    }

    @Test func fadesWithDistance() {
        #expect(ReportRelevance.score(report(), distanceMeters: 0, driverBearing: 100) == 80)
        #expect(ReportRelevance.score(report(), distanceMeters: 500, driverBearing: 100) == 40)
        #expect(ReportRelevance.score(report(), distanceMeters: 1000, driverBearing: 100) == 0)
    }

    @Test func weighsRoadAndDirection() {
        #expect(abs(ReportRelevance.score(report(), distanceMeters: 0, driverBearing: 100, onSameRoad: false) - 28) < 1e-9)
        #expect(ReportRelevance.directionFactor(report(direction: "opposite"), driverBearing: 90) == 0.15)
        #expect(ReportRelevance.directionFactor(report(direction: "opposite"), driverBearing: 270) == 1.0)
        #expect(ReportRelevance.directionFactor(report(bearing: nil), driverBearing: 90) == 0.75)
        #expect(ReportRelevance.directionFactor(report(), driverBearing: nil) == 0.75)
        #expect(ReportRelevance.directionFactor(report(), driverBearing: 180) == 0.75)
    }

    @Test func bandsTheScore() {
        #expect(ReportRelevance.band(of: 5) == .gone)
        #expect(ReportRelevance.band(of: 10) == .low)
        #expect(ReportRelevance.band(of: 30) == .normal)
        #expect(ReportRelevance.band(of: 60) == .high)
        #expect(ReportRelevance.label(.high) == "Forte pertinence")
    }
}

struct ReportModelTests {
    @Test func labelsAReport() {
        let fresh = UserReport(id: "a", type: .trafficJam, lat: 0, lon: 0, ageMillis: 30_000)
        #expect(fresh.ageLabel == "à l'instant")
        #expect(fresh.crowdLabel == "1 signalement · à l'instant")
        #expect(fresh.directionLabel == "Mon sens")
        #expect(fresh.sideLabel == nil)

        let old = UserReport(id: "b", type: .camera, lat: 0, lon: 0, ageMillis: 12 * 60_000, reporters: 3, direction: "opposite", score: 150, side: "left")
        #expect(old.crowdLabel == "3 signalements · il y a 12 min")
        #expect(old.directionLabel == "Sens opposé")
        #expect(old.sideLabel == "à gauche")
        #expect(old.confidence == 1)

        #expect(UserReport(id: "c", type: .hazard, lat: 0, lon: 0, ageMillis: 125 * 60_000).ageLabel == "il y a 2 h")
    }

    @Test func gatesTypesByRole() {
        #expect(!ReportType.voitureRadar.allowed(for: .guest))
        #expect(ReportType.voitureRadar.allowed(for: .client))
        #expect(!ReportType.camera.allowed(for: .client))
        #expect(ReportType.camera.allowed(for: .admin))
        #expect(ReportType.voitureRadar.needsPlate)
        #expect(ReportType.trafficJam.alertType == .hazard)
        #expect(ReportType(rawValue: "wrong_way") == .wrongWay)
        #expect(ReportType.picker.count == 14)
        #expect(ReportType.picker.last == .camera)
    }
}
