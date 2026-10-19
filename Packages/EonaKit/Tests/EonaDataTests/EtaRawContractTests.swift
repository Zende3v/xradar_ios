import Foundation
import Testing
import EonaCore
@testable import EonaData

/// Contrat ETA brut/corrigé : routes, envoi, file et reprise ; parrainage admin.
@MainActor
struct EtaRawContractTests {
    func route(_ body: String) async throws -> Route {
        try #require(try await RoutingAPI(client: backend(StubTransport(body: body)))
            .route(from: GeoPoint(lat: 0, lon: 0), to: GeoPoint(lat: 1, lon: 1), token: "t"))
    }

    @Test func rawEngineTimesStaySeparateFromTheShownTimes() async throws {
        let fresh = try await route(#"""
        {"coordinates":[[0,0],[1,1]],"distanceM":2000,"durationS":600,"engineDurationS":400,
         "steps":[{"location":[0,0],"type":"depart","distanceM":1000,"durationS":300,"engineDurationS":100},
                  {"location":[1,1],"type":"arrive","distanceM":1000,"durationS":300,"engineDurationS":300}]}
        """#)
        #expect(fresh.durationSeconds == 600)
        #expect(fresh.engineDurationSeconds == 400)
        #expect(fresh.steps.map(\.durationSeconds) == [300, 300])
        #expect(fresh.steps.map(\.engineDurationSeconds) == [100, 300])
    }

    @Test func anOlderBackendLeavesTheRawTimesUnknown() async throws {
        let old = try await route(#"""
        {"coordinates":[[0,0],[1,1]],"distanceM":2000,"durationS":600,
         "steps":[{"location":[0,0],"type":"depart","distanceM":1000,"durationS":300}]}
        """#)
        #expect(old.durationSeconds == 600)
        #expect(old.engineDurationSeconds == nil)
        #expect(old.steps.first?.engineDurationSeconds == nil)
        let nulls = try await route(#"{"coordinates":[[0,0],[1,1]],"distanceM":10,"durationS":5,"engineDurationS":null}"#)
        #expect(nulls.engineDurationSeconds == nil)
    }

    func measure(checks: [EtaCheck], timeline: [TripSample]) -> TripMeasure {
        TripMeasure(
            arrived: true, departedAt: 1, manualStart: false, plannedMeters: 2_000, pausedSeconds: 0, uncertainSeconds: 0,
            etaChecks: checks, recalcCount: 0, fasterCount: 0, engines: ["valhalla"], mapVersion: nil,
            appVersion: "1.0.0 (59)", platform: "ios", etaMode: "dynamic", trafficSources: [], timeline: timeline
        )
    }

    @Test func theRawMarkerGoesOutOnlyWithARawEngineTime() throws {
        let wire = AccountAPI.wireMeasure(measure(
            checks: [
                EtaCheck(at: 0, shownAt: 1, arrivalAt: 2, pausedBefore: 0, uncertainBefore: 0, base: "engine", engineLeftS: 300, engineBasis: "raw"),
                EtaCheck(at: 25, shownAt: 3, arrivalAt: 4, pausedBefore: 0, uncertainBefore: 0, base: "engine", engineLeftS: nil, engineBasis: "raw"),
                EtaCheck(at: 50, shownAt: 5, arrivalAt: 6, pausedBefore: 0, uncertainBefore: 0, base: "here", engineLeftS: 200, engineBasis: "eona"),
            ],
            timeline: [
                TripSample(t: 1, drivenM: 0, leftM: 2_000, leftS: 600, engineLeftS: 400, base: "engine", kmh: 30, engineBasis: "raw"),
                TripSample(t: 2, drivenM: 10, leftM: 1_990, leftS: 590, engineLeftS: 390, base: "engine", kmh: 30),
            ]
        ))
        let checks = try #require(wire["etaChecks"] as? [[String: Any]])
        #expect(checks[0]["engineBasis"] as? String == "raw")
        #expect(checks[1]["engineBasis"] == nil)
        #expect(checks[2]["engineBasis"] == nil)
        let timeline = try #require(wire["timeline"] as? [[String: Any]])
        #expect(timeline[0]["engineBasis"] as? String == "raw")
        #expect(timeline[1]["engineBasis"] is NSNull)
    }

    @Test func theRawMarkerSurvivesTheQueueAndTheRecovery() {
        let defaults = freshDefaults()
        let outbox = TripOutboxStore(defaults: defaults)
        let check = EtaCheck(at: 0, shownAt: 1, arrivalAt: 2, pausedBefore: 0, uncertainBefore: 0, base: "engine", engineLeftS: 300, engineBasis: "raw")
        let sample = TripSample(t: 1, drivenM: 0, leftM: 2_000, leftS: 600, engineLeftS: 400, base: "engine", kmh: 30, engineBasis: "raw")
        let trip = TripRecord(
            id: "t1", startedAt: 1, fromLabel: "A", toLabel: "B", distanceMeters: 2_000, durationSeconds: 600, alertsCount: 0, topSpeedKmh: 50,
            measure: measure(checks: [check], timeline: [sample])
        )
        outbox.add(trip, trace: [], countInStats: true, accountId: "A")
        outbox.keepRunning(trip, accountId: "A")
        let relaunch = TripOutboxStore(defaults: defaults)
        #expect(relaunch.pending.first?.trip.measure?.etaChecks.first?.engineBasis == "raw")
        #expect(relaunch.pending.first?.trip.measure?.timeline?.first?.engineBasis == "raw")
        #expect(relaunch.takeRunning()?.trip.measure?.etaChecks.first?.engineBasis == "raw")
    }

    @Test func olderMeasuresStillDecodeWithAnUnknownBasis() throws {
        let check = try JSONDecoder().decode(EtaCheck.self, from: Data(
            #"{"at":0,"shownAt":1,"arrivalAt":2,"pausedBefore":0,"uncertainBefore":0,"base":"engine","engineLeftS":300}"#.utf8
        ))
        #expect(check.engineLeftS == 300)
        #expect(check.engineBasis == nil)
        let sample = try JSONDecoder().decode(TripSample.self, from: Data(
            #"{"t":1,"drivenM":0,"leftM":10,"leftS":5,"engineLeftS":4,"base":"engine","kmh":20}"#.utf8
        ))
        #expect(sample.engineBasis == nil)
        let legacy = try #require(AccountAPI.wireMeasure(measure(checks: [check], timeline: [sample]))["etaChecks"] as? [[String: Any]])
        #expect(legacy.first?["engineBasis"] == nil)
    }

    @Test(arguments: ["extend", "revoke", "regenerate"])
    func referralActionsHitTheEncodedCode(action: String) async throws {
        let transport = StubTransport(body: #"{"referral":{"code":"A/B C?#%"}}"#)
        let months: Int? = action == "extend" ? 3 : nil
        let referral = await AccountAPI(client: backend(transport)).actOnReferral(code: "A/B C?#%", action: action, months: months, token: "adm")
        #expect(referral?.code == "A/B C?#%")
        let request = try #require(transport.last)
        #expect(request.httpMethod == "PATCH")
        #expect(request.path == "/api/accounts/referrals/A%2FB%20C%3F%23%25")
        #expect(request.jsonBody["action"] as? String == action)
        #expect(request.jsonBody["months"] as? Int == months)
        #expect(request.bearer == "Bearer adm")
    }
}
