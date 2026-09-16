import Foundation
import Testing
import XRadarCore
@testable import XRadarData

private func parsed(_ text: String) throws -> JSON {
    JSON(try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]))
}

struct TripDetailsTests {
    let trip = TripRecord(
        id: "t1", startedAt: 1_000, fromLabel: "Ma position", toLabel: "Rennes", distanceMeters: 12_000,
        durationSeconds: 900, alertsCount: 3, topSpeedKmh: 110, plannedSeconds: 840, stops: 2,
        stoppedSeconds: 75, events: [.radarFixed: 2, .accident: 1]
    )

    @Test func sentWithTheTrip() async throws {
        let transport = StubTransport(status: 201, body: "{}")
        #expect(await AccountAPI(client: backend(transport)).postTrip(token: "t", trip: trip))
        let body = try #require(transport.last).jsonBody
        #expect(body["plannedSeconds"] as? Int == 840)
        #expect(body["stops"] as? Int == 2)
        #expect(body["stoppedSeconds"] as? Int == 75)
        #expect(body["events"] as? [String: Int] == ["radarFixed": 2, "accident": 1])
    }

    @Test func readBackFromTheServer() throws {
        let stats = AccountAPI.stats(try parsed(#"""
        {"totals":{},"trips":[
          {"id":"t1","startedAt":1000,"toLabel":"Rennes","distanceMeters":12000,"durationSeconds":900,"alertsCount":3,
           "topSpeedKmh":110,"plannedSeconds":840,"stops":2,"stoppedSeconds":75,"events":{"radarFixed":2,"accident":1,"unknown":4,"camera":0}},
          {"id":"old","startedAt":1,"toLabel":"","distanceMeters":1,"durationSeconds":1,"alertsCount":0,"topSpeedKmh":0,"plannedSeconds":null}]}
        """#))
        let first = try #require(stats.trips.first)
        #expect(first.plannedSeconds == 840)
        #expect(first.stops == 2)
        #expect(first.stoppedSeconds == 75)
        #expect(first.events == [.radarFixed: 2, .accident: 1])
        let old = try #require(stats.trips.last)
        #expect(old.plannedSeconds == nil)
        #expect(old.stops == 0)
        #expect(old.events.isEmpty)
    }

    @Test func keptInTheLocalHistory() throws {
        let cached = try JSONDecoder().decode(StoredTrip.self, from: JSONEncoder().encode(StoredTrip(trip)))
        #expect(cached.trip == trip)
        let before = #"{"id":"o","startedAt":1,"fromLabel":"","toLabel":"","distanceMeters":1,"durationSeconds":1,"alertsCount":0,"topSpeedKmh":0}"#
        let old = try JSONDecoder().decode(StoredTrip.self, from: Data(before.utf8)).trip
        #expect(old.plannedSeconds == nil)
        #expect(old.stops == 0)
        #expect(old.events.isEmpty)
    }
}
