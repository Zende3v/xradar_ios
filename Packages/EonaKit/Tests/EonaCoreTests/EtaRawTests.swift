import Foundation
import Testing
@testable import EonaCore

/// Temps moteur brut, référence de mesure : séparé du temps EONA affiché.
struct EtaRawTests {
    func step(_ meters: Int, shown: Int, raw: Int?) -> RouteStep {
        RouteStep(
            location: GeoPoint(lat: 0, lon: 0), type: "turn", modifier: nil, name: "", distanceMeters: meters, exit: nil,
            durationSeconds: shown, engineDurationSeconds: raw
        )
    }

    func route(raw: Int?, steps: [RouteStep]) -> Route {
        Route(
            points: [GeoPoint(lat: 0, lon: 0), GeoPoint(lat: 0, lon: 0.02)], distanceMeters: 2_000, durationSeconds: 600,
            steps: steps, engineDurationSeconds: raw
        )
    }

    @Test func rawTimeLeftFollowsTheRawStepWeights() throws {
        // Étapes de même longueur : corrigé 300/300, brut 100/300.
        let measured = route(raw: 400, steps: [step(1_000, shown: 300, raw: 100), step(1_000, shown: 300, raw: 300)])
        let raw = try #require(EtaEstimator.rawSecondsLeft(route: measured, routeMeters: 2_000, along: 1_000))
        #expect(abs(raw - 300) < 0.001)
        #expect(abs(EtaEstimator.baseShareLeft(route: measured, routeMeters: 2_000, along: 1_000) - 0.5) < 0.001)
        #expect(abs((EtaEstimator.rawSecondsLeft(route: measured, routeMeters: 2_000, along: 0) ?? 0) - 400) < 0.001)
    }

    @Test func rawTimeLeftFallsBackToDistanceThenToUnknown() throws {
        let partial = route(raw: 400, steps: [step(1_000, shown: 300, raw: 100), step(1_000, shown: 300, raw: nil)])
        let byDistance = try #require(EtaEstimator.rawSecondsLeft(route: partial, routeMeters: 2_000, along: 1_000))
        #expect(abs(byDistance - 200) < 0.001)
        // Total brut inconnu : jamais le temps corrigé à sa place.
        let old = route(raw: nil, steps: [step(1_000, shown: 300, raw: 100), step(1_000, shown: 300, raw: 300)])
        #expect(EtaEstimator.rawSecondsLeft(route: old, routeMeters: 2_000, along: 1_000) == nil)
    }

    @Test func theShownEtaIgnoresTheRawTimes() {
        let steps = [step(1_000, shown: 300, raw: 100), step(1_000, shown: 300, raw: 300)]
        let withRaw = EtaEstimator.secondsLeft(route: route(raw: 400, steps: steps), routeMeters: 2_000, alongMeters: 500)
        let without = EtaEstimator.secondsLeft(
            route: route(raw: nil, steps: steps.map { step($0.distanceMeters, shown: $0.durationSeconds, raw: nil) }),
            routeMeters: 2_000, alongMeters: 500
        )
        #expect(withRaw == without)
    }

    @Test func recorderKeepsTheRawMarkerOnlyWithARawTime() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var recorder = TripRecorder(toLabel: "B", startedAt: start)
        let measured = route(raw: 400, steps: [])
        recorder.depart(
            route: measured, remainingShare: 1, manualStart: false, base: "engine", engineLeftSeconds: 400, engineBasis: EtaCheck.rawBasis, now: start
        )
        recorder.sample(leftMeters: 2_000, leftSeconds: 600, engineLeftSeconds: nil, base: "engine", engineBasis: EtaCheck.rawBasis, now: start)
        let measure = try #require(recorder.record(id: "t", keepShort: true, now: start)?.measure)
        let check = try #require(measure.etaChecks.first)
        #expect(check.engineLeftS == 400)
        #expect(check.engineBasis == "raw")
        #expect(measure.timeline?.first?.engineLeftS == nil)
        #expect(measure.timeline?.first?.engineBasis == nil)
        #expect(EtaCheck(at: 0, shownAt: 0, arrivalAt: 0, pausedBefore: 0, uncertainBefore: 0, engineLeftS: 5, engineBasis: "eona").engineBasis == nil)
    }
}
