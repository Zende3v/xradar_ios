import Foundation
import Testing
@testable import EonaData

struct AdminAPITests {
    @Test func overviewReadsUnavailableMetricsAndPartialHereHistory() async throws {
        let body = #"""
        {"generatedAt":"2026-10-05T20:00:00.000Z",
        "presence":{"ttlSeconds":90,"groups":[{"id":"free","label":"Gratuit","total":2,"online":1,"offline":1,"inTrip":0}],"online":1,"offline":1,"inTrip":0},
        "accounts":{"total":2,"banned":0,"suspended":0},"trips":{"retainedCount":0,"totalRecorded":0},
        "routing":{"provider":"valhalla","mode":"all","valhalla":{"state":"up","version":"3.9.0"},"fallbacks":{"total":1,"since":"2026-10-05T10:00:00.000Z"}},
        "routingStats":{"available":false,"retentionDays":90,"totalRequests":null,"totalErrors":null,"cacheHits":null,"weekRequests":null,"weekErrors":null,"medianMs":null,"p95Ms":null,"errorAttributionAvailable":false},
        "here":{"monthUsed":12,"dailyCap":null,"monthlyBudgetEUR":5,"estimatedMonthEUR":0.02,"blocked":null,"estimateOnly":true,
        "history":{"since":"2026-10-05T20:00:00.000Z","baselineMonth":"2026-10","totalRequests":12,"totalEstimatedEUR":0.02,"weekStart":"2026-10-05","weekRequests":0,"weekEstimatedEUR":0,"weekComplete":false,"earlierHistoryComplete":false}}}
        """#
        let transport = StubTransport(body: body)
        let overview = try await AdminAPI(client: backend(transport)).overview(token: "admin")
        #expect(overview.presence.groups.first?.id == "free")
        #expect(overview.routingStats.totalRequests == nil)
        #expect(overview.here.history.totalRequests == 12)
        #expect(!overview.here.history.weekComplete)
        #expect(transport.last?.value(forHTTPHeaderField: "Authorization") == "Bearer admin")
        #expect(transport.last?.query["deviceId"] == nil)
    }

    @Test func anonymousTripsReadLegacyArrivalAndPagination() async throws {
        let body = #"{"total":41,"count":1,"offset":40,"next":null,"retentionPerAccount":200,"trips":[{"id":"anonymous","startedAt":1791200000000,"distanceMeters":1234,"durationSeconds":120,"arrived":null,"engines":["valhalla"],"platform":null}]}"#
        let transport = StubTransport(body: body)
        let page = try await AdminAPI(client: backend(transport)).trips(offset: 40, token: "admin")
        #expect(page.trips.first?.arrived == nil)
        #expect(page.next == nil)
        #expect(page.retentionPerAccount == 200)
        #expect(transport.last?.query["offset"] == "40")
    }

    @Test func unbanAcceptsDeletedSourceAndKeepsSourceId() async throws {
        let transport = StubTransport(body: #"{"account":null,"revokedSessions":null,"unbanned":true}"#)
        let result = try await AdminAPI(client: backend(transport)).action(id: "deleted-source", action: "unban", token: "admin")
        #expect(result.account == nil)
        #expect(result.unbanned == true)
        #expect(transport.last?.path == "/api/admin/accounts/deleted-source/action")
        #expect(transport.last?.jsonBody["action"] as? String == "unban")
    }

    @Test func bansRegistryReadsDeletedAccounts() async throws {
        let body = #"{"total":1,"bans":[{"accountId":"deleted-source","accountExists":false,"displayName":null,"email":"blocked@example.invalid","bannedAt":"2026-10-05T10:00:00.000Z","reason":"Motif","deviceCount":2}]}"#
        let page = try await AdminAPI(client: backend(StubTransport(body: body))).bans(token: "admin")
        #expect(page.bans.first?.accountExists == false)
        #expect(page.bans.first?.deviceCount == 2)
    }

    @Test func missingAndRefusedSessionsNeverReadProtectedData() async {
        let transport = StubTransport(body: "{}")
        do {
            _ = try await AdminAPI(client: backend(transport)).overview(token: "")
            Issue.record("Session vide acceptée")
        } catch {
            guard case .some(.unauthorized) = error as? AdminAPIError else {
                Issue.record("Refus session vide non reconnu")
                return
            }
        }
        #expect(transport.last == nil)
        for status in [401, 403] {
            do {
                _ = try await AdminAPI(client: backend(StubTransport(status: status, body: "{}"))).overview(token: "expired")
                Issue.record("Session refusée acceptée")
            } catch {
                guard let failure = error as? AdminAPIError else { Issue.record("Erreur inattendue"); continue }
                switch failure {
                case .unauthorized: #expect(status == 401)
                case .forbidden: #expect(status == 403)
                default: Issue.record("Refus non reconnu")
                }
            }
        }
    }
}
