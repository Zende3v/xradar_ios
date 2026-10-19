import Foundation
import Testing
import EonaCore
@testable import EonaData

/// Faux backend : comptes "a"/"b" à la connexion (nouveau jeton à chaque fois), trajets et tracés
/// acceptés ou refusés, requêtes retenues sur demande jusqu'à libération.
final class GatedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var holds: [String: Int] = [:]
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var tripsOffline = false
    private var deleteStatus = 200
    private var logins = 0

    /// Prochaine requête sur [path] retenue.
    func hold(_ path: String) {
        lock.withLock { holds[path, default: 0] += 1 }
    }

    func release() {
        let held = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            defer { waiting = [] }
            return waiting
        }
        held.forEach { $0.resume() }
    }

    /// Libère seulement la plus ancienne requête retenue.
    func releaseOne() {
        let first = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            waiting.isEmpty ? nil : waiting.removeFirst()
        }
        first?.resume()
    }

    var heldCount: Int { lock.withLock { waiting.count } }
    var requests: [URLRequest] { lock.withLock { recorded } }

    func setTripsOffline(_ value: Bool) {
        lock.withLock { tripsOffline = value }
    }

    func setDeleteStatus(_ value: Int) {
        lock.withLock { deleteStatus = value }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path() ?? ""
        let mustHold = lock.withLock { () -> Bool in
            recorded.append(request)
            guard let count = holds[path], count > 0 else { return false }
            holds[path] = count - 1
            return true
        }
        if mustHold {
            await withCheckedContinuation { continuation in
                lock.withLock { waiting.append(continuation) }
            }
        }
        let (offline, deleteStatus) = lock.withLock { (tripsOffline, self.deleteStatus) }
        if offline, path.hasPrefix("/api/accounts/me/trips") { throw URLError(.notConnectedToInternet) }
        var status = 200
        var body = #"{"ok":true}"#
        if path == "/api/accounts/login" {
            let user = request.jsonBody["identifier"] as? String ?? "a"
            let n = lock.withLock { () -> Int in
                logins += 1
                return logins
            }
            body = #"{"account":\#(Self.account(user.uppercased())),"token":"t\#(user.uppercased())-\#(n)"}"#
        } else if path == "/api/accounts/me", request.httpMethod == "GET" {
            // Jeton "tA-1" : compte A.
            let id = String((request.bearer ?? "").dropFirst("Bearer t".count).prefix(1))
            body = #"{"account":\#(Self.account(id))}"#
        } else if path == "/api/accounts/me", request.httpMethod == "DELETE" {
            status = deleteStatus
            body = status == 200 ? #"{"ok":true}"# : #"{"error":"boom"}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(body.utf8), response)
    }

    static func account(_ id: String) -> String {
        #"{"id":"\#(id)","role":"client","username":"\#(id.lowercased())","access":"active"}"#
    }
}

/// Délais de renvoi demandés, rendus aussitôt ; délai bloqué : vrai sommeil long, annulable.
final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration] = []
    private var blocked: [Duration] = []

    var delays: [Duration] { lock.withLock { recorded } }

    func block(_ delay: Duration) {
        lock.withLock { blocked.append(delay) }
    }

    func sleep(_ delay: Duration) async throws {
        let mustBlock = lock.withLock { () -> Bool in
            recorded.append(delay)
            return blocked.contains(delay)
        }
        if mustBlock { try await Task.sleep(for: .seconds(3_600)) }
        await Task.yield()
    }
}

@MainActor
func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<2_000 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
}

extension URLRequest {
    var bearer: String? { value(forHTTPHeaderField: "Authorization") }
}

@MainActor
struct TripOutboxSenderTests {
    struct Rig {
        let transport: GatedTransport
        let account: AccountStore
        let outbox: TripOutboxStore
        let sender: TripOutboxSender
        let sleeps: SleepLog
        let defaults: UserDefaults
    }

    func rig() -> Rig {
        let transport = GatedTransport()
        let defaults = freshDefaults()
        let api = AccountAPI(client: BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://example.org/")!), transport: transport
        ))
        let account = AccountStore(api: api, secrets: MemorySecrets(), defaults: defaults)
        let outbox = TripOutboxStore(defaults: defaults)
        let sleeps = SleepLog()
        let sender = TripOutboxSender(outbox: outbox, account: account, api: api, sleep: { try await sleeps.sleep($0) })
        return Rig(transport: transport, account: account, outbox: outbox, sender: sender, sleeps: sleeps, defaults: defaults)
    }

    func trip(_ id: String) -> TripRecord {
        TripRecord(id: id, startedAt: 1, fromLabel: "A", toLabel: "B", distanceMeters: 1_000, durationSeconds: 60, alertsCount: 0, topSpeedKmh: 50)
    }

    func points(_ count: Int) -> [TracePoint] {
        (0..<count).map { TracePoint(t: $0, lat: 48, lon: 2, kmh: nil, accuracyM: nil, course: nil) }
    }

    func tripRequests(_ transport: GatedTransport) -> [URLRequest] {
        transport.requests.filter { ($0.url?.path() ?? "").hasPrefix("/api/accounts/me/trips") }
    }

    @Test func accountSwitchDuringATripPostNeverSendsUnderTheOtherToken() async {
        let rig = rig()
        _ = await rig.account.login(identifier: "a", password: "x")
        rig.outbox.add(trip("a1"), trace: points(1_500), countInStats: true, accountId: "A")
        rig.transport.hold("/api/accounts/me/trips")
        rig.sender.send()
        await waitUntil { rig.transport.heldCount == 1 }
        // B se connecte pendant l'attente ; l'observateur n'a pas encore réagi.
        _ = await rig.account.login(identifier: "b", password: "x")
        #expect(rig.account.session?.accountId == "B")
        rig.transport.release()
        await waitUntil { !rig.sender.isSending }
        let trips = tripRequests(rig.transport)
        #expect(trips.count == 1)
        #expect(trips.allSatisfy { $0.bearer == "Bearer tA-1" })
        // Aucun paquet de tracé après le changement ; trajet gardé pour A.
        #expect(!trips.contains { ($0.url?.path() ?? "").hasSuffix("/trace") })
        #expect(rig.outbox.holds("a1", accountId: "A"))
        // Session B suivie : rien de A ne part sous B.
        rig.sender.follow(rig.account.session)
        await waitUntil { !rig.sender.isSending }
        #expect(!tripRequests(rig.transport).contains { $0.bearer == "Bearer tB-2" })
        #expect(rig.outbox.holds("a1", accountId: "A"))
    }

    @Test func logoutThenReloginSameAccountResumesWithTheNewTokenOnly() async {
        let rig = rig()
        _ = await rig.account.login(identifier: "a", password: "x")
        rig.sender.follow(rig.account.session)
        rig.outbox.add(trip("a1"), trace: points(1_500), countInStats: true, accountId: "A")
        rig.transport.hold("/api/accounts/me/trips/a1/trace")
        rig.sender.send()
        await waitUntil { rig.transport.heldCount == 1 }
        rig.account.logout()
        rig.sender.follow(rig.account.session)
        #expect(!rig.sender.isSending)
        _ = await rig.account.login(identifier: "a", password: "x")
        let relogged = rig.account.session
        #expect(relogged?.accountId == "A")
        #expect(relogged?.token != "tA-1")
        rig.sender.follow(relogged)
        await waitUntil { rig.outbox.pending.isEmpty && !rig.sender.isSending }
        // Résultat tardif de l'ancienne session : ignoré, aucun paquet suivant sous l'ancien jeton.
        rig.transport.release()
        try? await Task.sleep(for: .milliseconds(20))
        let old = tripRequests(rig.transport).filter { $0.bearer == "Bearer tA-1" }
        #expect(old.count == 2)
        let fresh = tripRequests(rig.transport).filter { $0.bearer == "Bearer \(relogged?.token ?? "")" }
        #expect(fresh.map { $0.url?.path() ?? "" } == [
            "/api/accounts/me/trips", "/api/accounts/me/trips/a1/trace", "/api/accounts/me/trips/a1/trace",
        ])
        #expect(fresh.compactMap { $0.jsonBody["seq"] as? Int } == [0, 1])
        #expect(rig.outbox.pending.isEmpty)
    }

    @Test func aTripQueuedDuringASendIsSentByTheSameSender() async {
        let rig = rig()
        _ = await rig.account.login(identifier: "a", password: "x")
        rig.outbox.add(trip("a1"), trace: [], countInStats: true, accountId: "A")
        rig.transport.hold("/api/accounts/me/trips")
        rig.sender.send()
        await waitUntil { rig.transport.heldCount == 1 }
        rig.outbox.add(trip("a2"), trace: points(10), countInStats: true, accountId: "A")
        rig.sender.send()
        rig.sender.send()
        rig.transport.release()
        await waitUntil { rig.outbox.pending.isEmpty && !rig.sender.isSending }
        let posted = tripRequests(rig.transport).filter { $0.url?.path() == "/api/accounts/me/trips" }.compactMap { $0.jsonBody["id"] as? String }
        #expect(posted == ["a1", "a2"])
        #expect(rig.outbox.pending.isEmpty)
    }

    @Test func failuresRetryBoundedThenNetworkReturnResumes() async {
        let rig = rig()
        _ = await rig.account.login(identifier: "a", password: "x")
        rig.outbox.add(trip("a1"), trace: points(3), countInStats: true, accountId: "A")
        rig.transport.setTripsOffline(true)
        rig.sender.send()
        await waitUntil { !rig.sender.isSending }
        #expect(rig.sleeps.delays == TripOutboxSender.retryDelays)
        #expect(tripRequests(rig.transport).count == 1 + TripOutboxSender.retryDelays.count)
        #expect(rig.outbox.holds("a1", accountId: "A"))
        // Hors réseau : aucune tentative.
        rig.sender.setOnline(false)
        rig.transport.setTripsOffline(false)
        rig.sender.send()
        #expect(!rig.sender.isSending)
        #expect(tripRequests(rig.transport).count == 1 + TripOutboxSender.retryDelays.count)
        // Réseau revenu : reprise, trajet puis tracé.
        rig.sender.setOnline(true)
        await waitUntil { rig.outbox.pending.isEmpty && !rig.sender.isSending }
        #expect(rig.outbox.pending.isEmpty)
        #expect(tripRequests(rig.transport).last?.url?.path() == "/api/accounts/me/trips/a1/trace")
    }

    @Test func networkLossDuringATracePacketStopsTheNextOnes() async {
        let rig = rig()
        _ = await rig.account.login(identifier: "a", password: "x")
        rig.outbox.add(trip("a1"), trace: points(1_500), countInStats: true, accountId: "A")
        rig.transport.hold("/api/accounts/me/trips/a1/trace")
        rig.sender.send()
        await waitUntil { rig.transport.heldCount == 1 }
        rig.sender.setOnline(false)
        #expect(!rig.sender.isSending)
        // Réponse du paquet après la perte : aucun paquet suivant, rien retiré.
        rig.transport.release()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(tripRequests(rig.transport).count == 2)
        #expect(rig.outbox.holds("a1", accountId: "A"))
        #expect(!rig.sender.isSending)
        rig.sender.setOnline(true)
        await waitUntil { rig.outbox.pending.isEmpty && !rig.sender.isSending }
        #expect(rig.outbox.pending.isEmpty)
        #expect(tripRequests(rig.transport).compactMap { $0.jsonBody["seq"] as? Int } == [0, 0, 1])
    }

    @Test func aStaleResultAfterNetworkReturnNeitherRemovesNorResetsTheNewRunner() async {
        let rig = rig()
        _ = await rig.account.login(identifier: "a", password: "x")
        rig.outbox.add(trip("a1"), trace: points(1_500), countInStats: true, accountId: "A")
        rig.transport.hold("/api/accounts/me/trips/a1/trace")
        rig.transport.hold("/api/accounts/me/trips/a1/trace")
        rig.sender.send()
        await waitUntil { rig.transport.heldCount == 1 }
        rig.sender.setOnline(false)
        rig.sender.setOnline(true)
        #expect(rig.sender.isSending)
        // Nouvelle passe : trajet renvoyé (doublon ignoré par le serveur), paquet 0 retenu.
        await waitUntil { rig.transport.heldCount == 2 }
        rig.transport.releaseOne()
        try? await Task.sleep(for: .milliseconds(20))
        // Ancienne réponse : passe nouvelle intacte, trajet gardé, aucun paquet 1 de l'ancienne.
        #expect(rig.sender.isSending)
        #expect(rig.outbox.holds("a1", accountId: "A"))
        #expect(tripRequests(rig.transport).count == 4)
        rig.transport.release()
        await waitUntil { rig.outbox.pending.isEmpty && !rig.sender.isSending }
        #expect(rig.outbox.pending.isEmpty)
        #expect(tripRequests(rig.transport).map { $0.url?.path() ?? "" } == [
            "/api/accounts/me/trips", "/api/accounts/me/trips/a1/trace",
            "/api/accounts/me/trips", "/api/accounts/me/trips/a1/trace", "/api/accounts/me/trips/a1/trace",
        ])
        #expect(tripRequests(rig.transport).compactMap { $0.jsonBody["seq"] as? Int } == [0, 0, 1])
    }

    @Test func networkReturnDuringALongBackoffResumesAtOnce() async {
        let rig = rig()
        _ = await rig.account.login(identifier: "a", password: "x")
        rig.outbox.add(trip("a1"), trace: points(3), countInStats: true, accountId: "A")
        rig.transport.setTripsOffline(true)
        rig.sleeps.block(.seconds(600))
        rig.sender.send()
        // Deux renvois échoués, puis attente 600 s.
        await waitUntil { rig.sleeps.delays.count == TripOutboxSender.retryDelays.count }
        #expect(rig.sleeps.delays == TripOutboxSender.retryDelays)
        #expect(rig.sender.isSending)
        #expect(tripRequests(rig.transport).count == 3)
        rig.sender.setOnline(false)
        #expect(!rig.sender.isSending)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(tripRequests(rig.transport).count == 3)
        rig.transport.setTripsOffline(false)
        rig.sender.setOnline(true)
        await waitUntil { rig.outbox.pending.isEmpty && !rig.sender.isSending }
        #expect(rig.outbox.pending.isEmpty)
        #expect(tripRequests(rig.transport).count == 5)
        #expect(rig.sleeps.delays == TripOutboxSender.retryDelays)
    }

    @Test func anEmptyQueueStartsNothing() async {
        let rig = rig()
        _ = await rig.account.login(identifier: "a", password: "x")
        rig.outbox.add(trip("b1"), trace: [], countInStats: true, accountId: "B")
        rig.sender.send()
        #expect(!rig.sender.isSending)
        #expect(tripRequests(rig.transport).isEmpty)
    }

    @Test func sameTokenReloadKeepsTheSession() async {
        let rig = rig()
        _ = await rig.account.login(identifier: "a", password: "x")
        let before = rig.account.session
        await rig.account.reload()
        #expect(rig.account.session == before)
    }

    @Test func deletionPurgesOnlyTheDeletedAccountAndSurvivesARelaunch() async {
        let rig = rig()
        _ = await rig.account.login(identifier: "a", password: "x")
        rig.outbox.add(trip("a1"), trace: points(2), countInStats: true, accountId: "A")
        rig.outbox.add(trip("b1"), trace: points(2), countInStats: true, accountId: "B")
        rig.outbox.keepRunning(trip("a2"), trace: points(2), accountId: "A")
        var deleted: String?
        var closed = false
        #expect(await rig.account.deleteAccount(onDeleted: { id in
            deleted = id
            rig.outbox.purge(accountId: id)
        }, onClosed: { closed = true }) == nil)
        #expect(deleted == "A")
        #expect(closed)
        #expect(rig.account.session == nil)
        #expect(rig.outbox.pending.map(\.trip.id) == ["b1"])
        // Écritures tardives du trajet en cours de A : ignorées.
        rig.outbox.keepRunning(trip("a2"), trace: points(3), accountId: "A")
        rig.outbox.add(trip("a3"), trace: [], countInStats: true, accountId: "A")
        #expect(rig.outbox.pending.map(\.trip.id) == ["b1"])
        let relaunch = TripOutboxStore(defaults: rig.defaults)
        #expect(relaunch.pending.map(\.trip.id) == ["b1"])
        #expect(relaunch.takeRunning() == nil)
    }

    @Test func purgeKeepsAnotherAccountsRunningTrip() {
        let defaults = freshDefaults()
        let outbox = TripOutboxStore(defaults: defaults)
        outbox.keepRunning(trip("b2"), trace: points(1), accountId: "B")
        outbox.purge(accountId: "A")
        #expect(outbox.takeRunning()?.accountId == "B")
    }

    @Test func failedDeletionKeepsLocalTrips() async {
        let rig = rig()
        _ = await rig.account.login(identifier: "a", password: "x")
        rig.outbox.add(trip("a1"), trace: points(2), countInStats: true, accountId: "A")
        rig.outbox.keepRunning(trip("a2"), trace: points(2), accountId: "A")
        rig.transport.setDeleteStatus(500)
        var called = false
        let error = await rig.account.deleteAccount(onDeleted: { _ in called = true }, onClosed: { called = true })
        #expect(error != nil)
        #expect(!called)
        #expect(rig.account.session?.accountId == "A")
        #expect(rig.outbox.holds("a1", accountId: "A"))
        #expect(TripOutboxStore(defaults: rig.defaults).takeRunning()?.trip.id == "a2")
    }

    /// Suppression de A retenue au serveur, puis [change] de session ; succès tardif ensuite.
    func lateDeletion(_ change: @MainActor (Rig) async -> Void) async -> (rig: Rig, log: DeletionLog, history: TripHistoryStore, current: AccountSession?) {
        let rig = rig()
        _ = await rig.account.login(identifier: "a", password: "x")
        rig.outbox.add(trip("a1"), trace: points(2), countInStats: true, accountId: "A")
        rig.outbox.add(trip("b1"), trace: points(2), countInStats: true, accountId: "B")
        let history = TripHistoryStore(defaults: rig.defaults)
        history.add(trip("h1"))
        let (account, outbox, log) = (rig.account, rig.outbox, DeletionLog())
        rig.transport.hold("/api/accounts/me")
        let deletion = Task {
            await account.deleteAccount(
                onDeleted: { id in
                    log.deleted.append(id)
                    outbox.purge(accountId: id)
                },
                onClosed: {
                    log.closed += 1
                    history.removeAll()
                }
            )
        }
        await waitUntil { rig.transport.heldCount == 1 }
        await change(rig)
        let current = rig.account.session
        rig.transport.release()
        #expect(await deletion.value == nil)
        return (rig, log, history, current)
    }

    @Test func lateDeletionOfAPurgesAButKeepsTheSessionOfBAndTheHistory() async {
        let (rig, log, history, current) = await lateDeletion { rig in
            _ = await rig.account.login(identifier: "b", password: "x")
        }
        #expect(current?.accountId == "B")
        #expect(log.deleted == ["A"])
        #expect(log.closed == 0)
        #expect(rig.account.session == current)
        #expect(rig.outbox.pending.map(\.trip.id) == ["b1"])
        #expect(history.trips.map(\.id) == ["h1"])
    }

    @Test func lateDeletionOfAKeepsANewSessionOfA() async {
        let (rig, log, history, current) = await lateDeletion { rig in
            rig.account.logout()
            _ = await rig.account.login(identifier: "a", password: "x")
        }
        #expect(current?.accountId == "A")
        #expect(current?.token != "tA-1")
        #expect(log.deleted == ["A"])
        #expect(log.closed == 0)
        #expect(rig.account.session == current)
        #expect(rig.outbox.pending.map(\.trip.id) == ["b1"])
        #expect(history.trips.map(\.id) == ["h1"])
    }
}

/// Effets d'une suppression lancée en tâche : comptes purgés, fermetures de session.
@MainActor
final class DeletionLog {
    var deleted: [String] = []
    var closed = 0
}
