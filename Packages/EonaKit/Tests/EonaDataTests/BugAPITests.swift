import Foundation
import Testing
import EonaCore
@testable import EonaData

struct BugAPITests {
    let app = BugAppDetails(platform: "iOS", version: "1.0.0", os: "26.0", model: "iPhone17,1")

    @Test func aNavigationReportComesWithItsTrip() async throws {
        // A long wavy route: sent lighter, longitude first.
        let route = (0..<2_000).map { GeoPoint(lat: 48 + Double($0) * 0.0001, lon: -1.6 + sin(Double($0) / 10) * 0.001) }
        let context = BugContext(engine: "ors", mapVersion: "2026-09-20", trip: BugTripContext(
            inProgress: true, toLabel: "Nantes", startedAt: 1_000, departedAt: nil, distanceMeters: 4_200, plannedMeters: nil,
            destination: GeoPoint(lat: 47.2, lon: -1.55), route: route
        ))
        let transport = StubTransport(status: 201, body: "{}")
        let outcome = await BugAPI(client: backend(transport)).send(
            category: .navigation, description: "Demi-tour bizarre", steps: nil, app: app, context: context, token: "t"
        )
        #expect(outcome == .sent)
        let sent = try #require(transport.last?.jsonBody["context"] as? [String: Any])
        #expect(sent["engine"] as? String == "ors")
        #expect(sent["mapVersion"] as? String == "2026-09-20")
        let trip = try #require(sent["trip"] as? [String: Any])
        #expect(trip["inProgress"] as? Bool == true)
        #expect(trip["toLabel"] as? String == "Nantes")
        #expect(trip["startedAt"] as? Int == 1_000)
        #expect(trip["departedAt"] is NSNull)
        #expect(trip["distanceMeters"] as? Int == 4_200)
        #expect(trip["plannedMeters"] is NSNull)
        #expect(trip["destination"] as? [String: Double] == ["lat": 47.2, "lon": -1.55])
        let line = try #require(trip["route"] as? [[Double]])
        #expect((2...BugAPI.maxRoutePoints).contains(line.count))
        #expect(line.first == [-1.6, 48])
    }

    @Test func onlyANavigationReportCarriesTheContext() async throws {
        let other = StubTransport(status: 201, body: "{}")
        _ = await BugAPI(client: backend(other)).send(
            category: .map, description: "Carte vide", steps: nil, app: app, context: BugContext.empty, token: nil
        )
        #expect(other.last?.jsonBody.keys.contains("context") == false)

        // No trip since the app started: everything null.
        let none = StubTransport(status: 201, body: "{}")
        _ = await BugAPI(client: backend(none)).send(
            category: .navigation, description: "Pas de route", steps: nil, app: app, context: BugContext.empty, token: nil
        )
        let context = try #require(none.last?.jsonBody["context"] as? [String: Any])
        #expect(context["engine"] is NSNull)
        #expect(context["mapVersion"] is NSNull)
        #expect(context["trip"] is NSNull)
    }
}
