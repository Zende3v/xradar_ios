import Foundation
import Testing
import EonaCore
@testable import EonaData

struct AccountAPITests {
    let accountBody = #"""
    {"account":{"id":"u1","role":"client","username":"arthur","displayName":null,"avatarUrl":"","email":"a@b.fr",
    "banned":false,"emailVerified":true,"access":"active","canNavigate":true,"accessEndsAt":"2026-10-01T00:00:00Z","trust":4.2},
    "token":"t0k"}
    """#

    @Test func loginSendsTheIdentifierAndReadsTheAccount() async throws {
        let transport = StubTransport(body: accountBody)
        let outcome = await AccountAPI(client: backend(transport)).login(identifier: "arthur", password: "secret123", deviceId: "dev-1")
        guard case .success(let auth) = outcome else {
            Issue.record("expected a success, got \(outcome)")
            return
        }
        #expect(auth.token == "t0k")
        #expect(auth.account.role == .client)
        #expect(auth.account.username == "arthur")
        #expect(auth.account.displayName == nil)
        #expect(auth.account.avatarUrl == nil)
        #expect(auth.account.access == .active)
        #expect(auth.account.trust == 4.2)
        let request = try #require(transport.last)
        #expect(request.httpMethod == "POST")
        #expect(request.path == "/api/accounts/login")
        #expect(request.jsonBody["identifier"] as? String == "arthur")
        #expect(request.jsonBody["password"] as? String == "secret123")
        #expect(request.jsonBody["deviceId"] as? String == "dev-1")
    }

    @Test func failuresReadForTheDriver() async {
        let refused = StubTransport(status: 401, body: #"{"error":"invalid credentials"}"#)
        #expect(await AccountAPI(client: backend(refused)).login(identifier: "a", password: "b", deviceId: nil)
            == AuthOutcome.failure("Identifiant ou mot de passe incorrect."))

        let offline = StubTransport { _ in throw URLError(.notConnectedToInternet) }
        #expect(await AccountAPI(client: backend(offline)).login(identifier: "a", password: "b", deviceId: nil)
            == AuthOutcome.failure("Réseau indisponible"))

        #expect(await AccountAPI(client: backend(StubTransport(body: "{}"))).claimGuest(deviceId: "d", username: "u", password: "p")
            == AuthOutcome.failure("Réponse invalide"))
        #expect(AccountAPI.friendly("oops") == "Oops")
        #expect(await AccountAPI(client: backend(StubTransport(status: 400, body: #"{"error":"invalid code"}"#))).verify(email: "a@b.fr", code: "1")
            == "Invalid code")
    }

    @Test func deviceSignInSaysItIsTheIOSApp() async {
        let transport = StubTransport(body: accountBody)
        let auth = await AccountAPI(client: backend(transport)).authDevice(deviceId: "dev-1")
        #expect(auth?.token == "t0k")
        #expect(transport.last?.path == "/api/accounts/auth")
        #expect(transport.last?.jsonBody["platform"] as? String == "ios")
        #expect(await AccountAPI(client: backend(StubTransport(status: 500, body: ""))).authDevice(deviceId: "dev-1") == nil)
    }

    @Test func statsProfileAndSession() async throws {
        let statsBody = #"""
        {"totals":{"tripCount":3,"distanceMeters":45000,"driveDurationSeconds":3600,"alertsTraversed":7,"reportsDeclared":2,"reportsConfirmed":1},
        "trust":3.5,
        "trips":[{"id":"t1","startedAt":1789344000000,"fromLabel":"Rennes","toLabel":"Nantes","distanceMeters":110000,"durationSeconds":4200,"alertsCount":4,"topSpeedKmh":131},
        {"id":"t2","startedAt":1789344000000,"fromLabel":"Ma position","toLabel":"Vannes","distanceMeters":9000,"durationSeconds":700,"alertsCount":0,"topSpeedKmh":80,
        "arrived":true,"departedAt":1789344060000,"manualStart":false,"retargeted":true,"plannedMeters":8800,"pausedSeconds":0,"uncertainSeconds":320,
        "etaChecks":[{"at":0,"shownAt":1789344060000,"arrivalAt":1789344700000,"pausedBefore":0,"uncertainBefore":0}],
        "recalcCount":1,"fasterCount":0,"engines":["ors"],"mapVersion":null,"appVersion":"1.0.0 (2)","platform":"ios","etaMode":"proportional","trafficSources":["tomtom"]}]}
        """#
        let transport = StubTransport(body: statsBody)
        let stats = try #require(await AccountAPI(client: backend(transport)).stats(token: "t0k"))
        #expect(stats.tripCount == 3)
        #expect(stats.driveSeconds == 3600)
        #expect(stats.trust == 3.5)
        #expect(stats.trips.first?.toLabel == "Nantes")
        #expect(stats.trips.first?.startedAt == 1_789_344_000_000)
        // A trip sent before the measures reads without them; a later one keeps them all.
        #expect(stats.trips.first?.measure == nil)
        let measure = try #require(stats.trips.last?.measure)
        #expect(measure.arrived && measure.retargeted == true && !measure.manualStart)
        #expect(measure.departedAt == 1_789_344_060_000)
        #expect(measure.plannedMeters == 8_800)
        #expect(measure.uncertainSeconds == 320)
        #expect(measure.etaChecks == [EtaCheck(at: 0, shownAt: 1_789_344_060_000, arrivalAt: 1_789_344_700_000, pausedBefore: 0, uncertainBefore: 0)])
        #expect(measure.engines == ["ors"] && measure.mapVersion == nil && measure.trafficSources == ["tomtom"])
        #expect(measure.appVersion == "1.0.0 (2)" && measure.etaMode == "proportional")
        #expect(transport.last?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")

        let patch = StubTransport(body: accountBody)
        _ = await AccountAPI(client: backend(patch)).updateProfile(token: "t0k", username: "neo", avatarUrl: nil)
        #expect(patch.last?.httpMethod == "PATCH")
        #expect(patch.last?.jsonBody.keys.sorted() == ["username"])

        #expect(try await AccountAPI(client: backend(StubTransport(status: 401, body: "{}"))).me(token: "old") == nil)
        await #expect(throws: URLError.self) {
            try await AccountAPI(client: backend(StubTransport(status: 502, body: ""))).me(token: "t0k")
        }
        #expect(try await AccountAPI(client: backend(StubTransport(body: accountBody))).me(token: "t0k")?.id == "u1")
    }

    @Test func aTripGoesWithItsMeasures() async throws {
        let measure = TripMeasure(
            arrived: true, departedAt: 1_789_000_060_000, manualStart: false, plannedMeters: 12_300,
            pausedSeconds: 360, uncertainSeconds: 0,
            etaChecks: [EtaCheck(at: 0, shownAt: 1_789_000_060_000, arrivalAt: 1_789_000_960_000, pausedBefore: 0, uncertainBefore: 0)],
            recalcCount: 2, fasterCount: 1, engines: ["ors", "unknown"], mapVersion: nil,
            appVersion: "1.0.0 (1)", platform: "ios", etaMode: "proportional", trafficSources: ["tomtom", "crowd"]
        )
        let trip = TripRecord(
            id: "t1", startedAt: 1_789_000_000_000, fromLabel: "Ma position", toLabel: "Nantes", distanceMeters: 12_000,
            durationSeconds: 1_300, alertsCount: 0, topSpeedKmh: 90, measure: measure
        )
        let transport = StubTransport(status: 201, body: "{}")
        #expect(await AccountAPI(client: backend(transport)).postTrip(token: "t0k", trip: trip))
        let body = try #require(transport.last).jsonBody
        #expect(body["arrived"] as? Bool == true)
        #expect(body["departedAt"] as? Int == 1_789_000_060_000)
        #expect(body["manualStart"] as? Bool == false)
        #expect(body["plannedMeters"] as? Int == 12_300)
        #expect(body["pausedSeconds"] as? Int == 360)
        #expect(body["uncertainSeconds"] as? Int == 0)
        #expect(body["etaChecks"] as? [[String: Int]] == [
            ["at": 0, "shownAt": 1_789_000_060_000, "arrivalAt": 1_789_000_960_000, "pausedBefore": 0, "uncertainBefore": 0],
        ])
        #expect(body["recalcCount"] as? Int == 2)
        #expect(body["fasterCount"] as? Int == 1)
        #expect(body["engines"] as? [String] == ["ors", "unknown"])
        #expect(body["mapVersion"] is NSNull)
        #expect(body["appVersion"] as? String == "1.0.0 (1)")
        #expect(body["platform"] as? String == "ios")
        #expect(body["etaMode"] as? String == "proportional")
        #expect(body["trafficSources"] as? [String] == ["tomtom", "crowd"])
        #expect(body["retargeted"] as? Bool == false)
        // Nothing else goes: no coordinates.
        #expect(Set(body.keys) == [
            "id", "startedAt", "fromLabel", "toLabel", "distanceMeters", "durationSeconds", "alertsCount", "topSpeedKmh",
            "stops", "stoppedSeconds", "events",
            "arrived", "departedAt", "manualStart", "plannedMeters", "pausedSeconds", "uncertainSeconds", "etaChecks",
            "recalcCount", "fasterCount", "engines", "mapVersion", "appVersion", "platform", "etaMode", "trafficSources",
            "retargeted",
        ])

        // A trip recorded before the measures goes as it always did.
        let old = StubTransport(status: 201, body: "{}")
        let before = TripRecord(
            id: "o", startedAt: 1, fromLabel: "", toLabel: "", distanceMeters: 1_000, durationSeconds: 60, alertsCount: 0, topSpeedKmh: 50
        )
        #expect(await AccountAPI(client: backend(old)).postTrip(token: "t0k", trip: before))
        let sent = try #require(old.last)
        #expect(sent.jsonBody.keys.sorted() == [
            "alertsCount", "distanceMeters", "durationSeconds", "events", "fromLabel", "id", "startedAt", "stoppedSeconds", "stops",
            "toLabel", "topSpeedKmh",
        ])
    }

    @Test func deletingTheAccount() async {
        let transport = StubTransport(body: #"{"deleted":true}"#)
        #expect(await AccountAPI(client: backend(transport)).deleteAccount(token: "t0k") == nil)
        #expect(transport.last?.httpMethod == "DELETE")
        #expect(transport.last?.path == "/api/accounts/me")
        #expect(transport.last?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
        let failed = StubTransport(status: 500, body: #"{"error":"could not delete account"}"#)
        #expect(await AccountAPI(client: backend(failed)).deleteAccount(token: "t0k") != nil)
    }
}
