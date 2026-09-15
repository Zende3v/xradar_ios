import Foundation
import Testing
import XRadarCore
@testable import XRadarData

struct RoadAPITests {
    @Test func routeSignsSendLongitudeFirst() async throws {
        let transport = StubTransport(body: #"{"signs":[{"type":"speed","lat":48,"lon":-1,"v":50},{"type":"stop","lat":48.1,"lon":-1.1},{"type":"nope"}]}"#)
        let signs = await SignAPI(client: backend(transport)).route([GeoPoint(lat: 48, lon: -1), GeoPoint(lat: 48.5, lon: -1.5)])
        #expect(signs == [RoadSign(type: .speedLimit, lat: 48, lon: -1, speed: 50), RoadSign(type: .stop, lat: 48.1, lon: -1.1)])
        let coordinates = try #require(transport.last?.jsonBody["coordinates"] as? [[Double]])
        #expect(coordinates == [[-1, 48], [-1.5, 48.5]])
        #expect(await SignAPI(client: backend(transport)).route([GeoPoint(lat: 1, lon: 1)]) == [])
        #expect(await SignAPI(client: backend(StubTransport(status: 502, body: ""))).route([GeoPoint(lat: 0, lon: 0), GeoPoint(lat: 1, lon: 1)]) == nil)
    }

    @Test func limitUnderTheDriver() async {
        let transport = StubTransport(body: #"{"v":80,"way":"123456","source":"postgis"}"#)
        let limit = await SignAPI(client: backend(transport)).limit(lat: 48, lon: -1, bearingDeg: 90.5, previousWayId: "99")
        #expect(limit == RoadLimit(kmh: 80, wayId: "123456"))
        #expect(transport.last?.query == ["lat": "48.0", "lon": "-1.0", "bearing": "90.5", "way": "99"])
        #expect(await SignAPI(client: backend(StubTransport(body: #"{"v":null,"way":null}"#))).limit(lat: 0, lon: 0) == RoadLimit(kmh: nil, wayId: nil))
        #expect(await SignAPI(client: backend(StubTransport(body: #"{"v":200}"#))).limit(lat: 0, lon: 0)?.kmh == nil)
        #expect(await SignAPI(client: backend(StubTransport(status: 503, body: "{}"))).limit(lat: 0, lon: 0) == nil)
    }

    @Test func routeReadsLongitudeFirstAndSteps() async throws {
        let body = #"""
        {"coordinates":[[-1.68,48.11],[-1.60,48.12],[-1.55]],"distanceM":1234,"durationS":300,
         "steps":[{"location":[-1.60,48.12],"type":"turn","modifier":"right","name":"Rue X","distanceM":500,"exit":null},{"type":"arrive"}]}
        """#
        let transport = StubTransport(body: body)
        let route = try #require(try await RoutingAPI(client: backend(transport))
            .route(from: GeoPoint(lat: 48.11, lon: -1.68), to: GeoPoint(lat: 48.12, lon: -1.6), avoid: ["tolls", "highways"], token: "t0k"))
        #expect(route.points == [GeoPoint(lat: 48.11, lon: -1.68), GeoPoint(lat: 48.12, lon: -1.6)])
        #expect(route.distanceMeters == 1234)
        #expect(route.durationSeconds == 300)
        #expect(route.steps == [RouteStep(location: GeoPoint(lat: 48.12, lon: -1.6), type: "turn", modifier: "right", name: "Rue X", distanceMeters: 500, exit: nil)])
        #expect(transport.last?.query == ["from": "48.11,-1.68", "to": "48.12,-1.6", "avoid": "tolls,highways"])
        #expect(transport.last?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
    }

    @Test func radars() async throws {
        let transport = StubTransport(body: #"{"radars":[{"id":"a","type":"ETFR","vma":null,"lat":43.6,"lon":3.8}]}"#)
        #expect(try await RadarAPI(client: backend(transport)).near(lat: 43.6, lon: 3.8, radiusM: 5000)
            == [Radar(id: "a", code: "ETFR", vma: nil, lat: 43.6, lon: 3.8)])
        #expect(try await RadarAPI(client: backend(StubTransport(status: 404, body: ""))).route([GeoPoint(lat: 0, lon: 0), GeoPoint(lat: 1, lon: 1)]) == nil)
    }

    @Test func speedLimitProposal() async throws {
        let transport = StubTransport(status: 201, body: #"{"change":{"id":"c1","status":"pending","oldKmh":80,"newKmh":null,"reporters":1,"required":3}}"#)
        let proposal = NewSpeedLimitReport(lat: 48, lon: -1, bearingDeg: 10, displayedKmh: 80, displayedSource: .road, newKmh: 50)
        let change = try await SpeedLimitAPI(client: backend(transport)).report(proposal, token: "t", deviceId: "d")
        #expect(change == SpeedLimitChange(id: "c1", status: .pending, oldKmh: 80, newKmh: nil, reporters: 1, required: 3))
        #expect(transport.last?.jsonBody["displayedSource"] as? String == "map")
        #expect(transport.last?.jsonBody["newKmh"] as? Int == 50)
    }

    @Test func liveDrivers() async {
        let transport = StubTransport(body: #"{"users":[{"id":"u2","username":"","lat":48,"lon":-1,"bearing":null,"avatarUrl":"https://x/a.jpg"}]}"#)
        #expect(await LiveAPI(client: backend(transport)).near(token: "t", lat: 48, lon: -1, radiusM: 3000)
            == [LiveUser(id: "u2", username: nil, lat: 48, lon: -1, bearingDeg: nil, avatarUrl: "https://x/a.jpg")])
        #expect(await LiveAPI(client: backend(StubTransport(status: 500, body: ""))).near(token: "t", lat: 0, lon: 0, radiusM: 1) == nil)
        #expect(await LiveAPI(client: backend(StubTransport(status: 500, body: ""))).share(token: "t", lat: 0, lon: 0, bearing: nil, speedKmh: nil, visible: true) == false)
    }
}

struct PlacesAPITests {
    @Test func fuelStationsWithPricesAndHours() async throws {
        let body = #"""
        {"count":2,"places":[
          {"id":"way/1","kind":"fuel","name":"Total Access","brand":"TotalEnergies","subtitle":"12 Rue de Nantes, Rennes",
           "lat":48.1,"lon":-1.6,"distanceM":850,"customersOnly":false,
           "hours":{"state":"open","alwaysOpen":false,"today":[{"from":"07:00","to":"21:00"}],"nextAt":1789412400000,"source":"official"},
           "fuel":{"stationId":"35000001","matchedBy":"id","prices":[
             {"fuel":"Gazole","price":1.759,"updatedAt":"2026-09-14T09:29:05+02:00","outOfStock":false},{"fuel":"Kérosène","price":2}]}},
          {"id":"node/2","kind":"fuel","name":"","lat":0,"lon":0}]}
        """#
        let transport = StubTransport(body: body)
        let places = try #require(await PlacesAPI(client: backend(transport)).near(category: .fuel, lat: 48.1, lon: -1.6))
        let station = try #require(places.first)
        #expect(places.count == 1)
        #expect(station.distanceMeters == 850)
        #expect(station.subtitle == "12 Rue de Nantes, Rennes")
        #expect(station.nearby?.brand == "TotalEnergies")
        #expect(station.nearby?.hours == OpeningHours(
            state: .open, alwaysOpen: false, today: [TimeSlot(from: "07:00", to: "21:00")], nextChangeMillis: 1_789_412_400_000, official: true
        ))
        #expect(station.fuel?.prices.map(\.type) == [.gazole])
        #expect(transport.last?.query == ["lat": "48.1", "lon": "-1.6", "kind": "fuel", "pool": "1"])
    }

    @Test func chargersAndCarParks() async throws {
        let body = #"""
        {"places":[
          {"id":"n1","name":"Ionity","lat":1,"lon":2,"charging":{"maxKw":350,"connectors":["CCS",""],"points":null},"stars":7,
           "fuel":{"stationId":"x","prices":[]}},
          {"id":"n2","name":"Hoche","lat":1,"lon":2,"parking":{"fee":true,"type":"multi_storey","capacity":777,"parkAndRide":false},
           "customersOnly":true,"hours":null}]}
        """#
        let places = try #require(await PlacesAPI(client: backend(StubTransport(body: body))).near(category: .parking, lat: 1, lon: 2))
        #expect(places[0].nearby?.charging == ChargingInfo(maxKw: 350, connectors: ["CCS"], points: nil))
        #expect(places[0].nearby?.stars == nil)
        #expect(places[0].fuel == nil)
        #expect(places[1].nearby?.parking == ParkingInfo(fee: true, type: .multiStorey, capacity: 777, parkAndRide: false))
        #expect(places[1].nearby?.customersOnly == true)
        #expect(places[1].nearby?.hours == nil)
        #expect(await PlacesAPI(client: backend(StubTransport(status: 503, body: "{}"))).near(category: .atm, lat: 1, lon: 2) == nil)
    }

    @Test func addressSearchEncodesTheQuery() async throws {
        let body = #"""
        {"features":[
          {"geometry":{"coordinates":[-1.6778,48.1113]},"properties":{"id":"35238_1","label":"Place de la Mairie 35000 Rennes","context":"35, Ille-et-Vilaine, Bretagne"}},
          {"geometry":{},"properties":{}}]}
        """#
        let transport = StubTransport(body: body)
        let places = try await GeocodingAPI(transport: transport).search("rue de la gare & co", aroundLat: 48.1, aroundLon: -1.6)
        #expect(places == [Place(
            id: "35238_1", name: "Place de la Mairie 35000 Rennes", subtitle: "35, Ille-et-Vilaine, Bretagne", kind: .result, lat: 48.1113, lon: -1.6778
        )])
        let url = try #require(transport.last?.url)
        #expect(url.host() == "api-adresse.data.gouv.fr")
        #expect(transport.last?.query["q"] == "rue de la gare & co")
        #expect(url.absoluteString.contains("q=rue%20de%20la%20gare%20%26%20co"))
    }
}
