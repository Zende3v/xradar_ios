import Foundation
import Testing
import XRadarCore
@testable import XRadarData

struct ReportsAPITests {
    @Test func nearReadsReportsAndZones() async throws {
        let body = #"""
        {"reports":[
          {"id":"r1","type":"radar_mobile","lat":48.1,"lon":-1.6,"createdAt":1789410000000,"confirmations":2,"contradictions":1,
           "reporters":3,"direction":"opposite","bearing":92.5,"score":64,"impactM":1500,"persistent":false,"reporterRole":"client",
           "street":null,"side":null},
          {"id":"r2","type":"unknown_type"}],
         "zones":[{"id":"z1","lat":48.2,"lon":-1.7,"radiusM":800,"count":4},{"lat":1}]}
        """#
        let transport = StubTransport(body: body)
        let now = Date(timeIntervalSince1970: 1_789_410_060)
        let near = try await ReportsAPI(client: backend(transport)).near(lat: 48.1113, lon: -1.6778, radiusM: 5000, now: now)
        let report = try #require(near.reports.first)
        #expect(near.reports.count == 1)
        #expect(report.type == .radarMobile)
        #expect(report.ageMillis == 60_000)
        #expect(report.reporters == 3)
        #expect(report.direction == "opposite")
        #expect(report.bearingDeg == 92.5)
        #expect(report.reporterRole == "client")
        #expect(report.street == nil)
        #expect(near.zones == [RadarZone(id: "z1", lat: 48.2, lon: -1.7, radiusMeters: 800, count: 4)])
        #expect(transport.last?.query == ["lat": "48.1113", "lon": "-1.6778", "radius": "5000"])
    }

    @Test func createSendsTheReport() async throws {
        let transport = StubTransport(status: 201, body: #"{"merged":false,"report":{"id":"r9","type":"accident","lat":48,"lon":-1,"createdAt":0,"score":80}}"#)
        let created = try await ReportsAPI(client: backend(transport))
            .create(NewReport(type: .accident, lat: 48, lon: -1, bearingDeg: 181), token: "t0k", deviceId: "dev-1")
        #expect(created?.id == "r9")
        let body = try #require(transport.last).jsonBody
        #expect(body["type"] as? String == "accident")
        #expect(body["bearing"] as? Double == 181)
        #expect(body["direction"] as? String == "same")
        #expect(body["deviceId"] as? String == "dev-1")
        #expect(body["plate"] == nil)
        #expect(transport.last?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
        #expect(try await ReportsAPI(client: backend(StubTransport(status: 403, body: "{}"))).create(NewReport(type: .camera, lat: 0, lon: 0), token: nil, deviceId: nil) == nil)
    }

    @Test func votesGoToConfirmOrDeny() async throws {
        let transport = StubTransport(body: "{}")
        let api = ReportsAPI(client: backend(transport))
        #expect(try await api.vote(id: "r 1", confirm: true, token: "t", deviceId: "d"))
        #expect(transport.last?.path == "/api/reports/r%201/confirm")
        #expect(try await api.vote(id: "r1", confirm: false, token: nil, deviceId: nil))
        #expect(transport.last?.path == "/api/reports/r1/deny")
        #expect(try await api.delete(id: "r1", token: "admin"))
        #expect(transport.last?.httpMethod == "DELETE")
    }
}
