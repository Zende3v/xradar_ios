import Foundation
import Testing
import XRadarCore
@testable import XRadarData

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
        "trips":[{"id":"t1","startedAt":1789344000000,"fromLabel":"Rennes","toLabel":"Nantes","distanceMeters":110000,"durationSeconds":4200,"alertsCount":4,"topSpeedKmh":131}]}
        """#
        let transport = StubTransport(body: statsBody)
        let stats = try #require(await AccountAPI(client: backend(transport)).stats(token: "t0k"))
        #expect(stats.tripCount == 3)
        #expect(stats.driveSeconds == 3600)
        #expect(stats.trust == 3.5)
        #expect(stats.trips.first?.toLabel == "Nantes")
        #expect(stats.trips.first?.startedAt == 1_789_344_000_000)
        #expect(transport.last?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")

        let patch = StubTransport(body: accountBody)
        _ = await AccountAPI(client: backend(patch)).updateProfile(token: "t0k", username: "neo", avatarUrl: nil)
        #expect(patch.last?.httpMethod == "PATCH")
        #expect(patch.last?.jsonBody.keys.sorted() == ["username"])

        #expect(try await AccountAPI(client: backend(StubTransport(status: 401, body: "{}"))).me(token: "old") == nil)
        #expect(try await AccountAPI(client: backend(StubTransport(body: accountBody))).me(token: "t0k")?.id == "u1")
    }
}
