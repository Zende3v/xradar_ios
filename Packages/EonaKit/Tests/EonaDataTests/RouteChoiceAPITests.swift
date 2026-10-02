import Foundation
import Testing
import EonaCore
@testable import EonaData

struct RouteChoiceAPITests {
    private let a = GeoPoint(lat: 0, lon: 0)
    private let b = GeoPoint(lat: 1, lon: 1)

    @Test func asksChoiceAndHereTimeThenReadsThem() async throws {
        let transport = StubTransport(body: #"{"coordinates":[[0,0],[1,1]],"distanceM":10,"durationS":5,"preference":"shortest","travelS":620}"#)
        let route = try #require(try await RoutingAPI(client: backend(transport)).route(from: a, to: b, preference: .shortest, timed: true, token: "t"))
        #expect(transport.last?.query["preference"] == "shortest")
        #expect(transport.last?.query["timed"] == "1")
        #expect(route.preference == .shortest)
        #expect(route.trafficSeconds == 620)
        // Backend sans choix d'itinéraire, ou HERE muet.
        let old = try #require(try await RoutingAPI(client: backend(StubTransport(body: #"{"coordinates":[[0,0],[1,1]],"distanceM":10,"durationS":5,"travelS":null}"#)))
            .route(from: a, to: b, token: "t"))
        #expect(old.preference == nil)
        #expect(old.trafficSeconds == nil)
        #expect(old.expectedSeconds == 5)
    }

    @Test func fasterSendsTheTripMode() async {
        let transport = StubTransport(body: #"{"better":null,"reason":"no significant jam"}"#)
        let none = await RoutingAPI(client: backend(transport)).faster([a, b], avoid: [], sinceRerouteSeconds: nil, preference: .shortest, token: "t")
        #expect(none == nil)
        #expect(transport.last?.jsonBody["preference"] as? String == "shortest")
    }
}
