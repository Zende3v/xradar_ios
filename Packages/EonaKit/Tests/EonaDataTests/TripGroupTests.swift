import Foundation
import Testing
import EonaCore
@testable import EonaData

/// "Trajet en groupe": what the backend says is read as the screens expect it, a participant who
/// does not share gives nothing away, and the ranking survives in the history.
@MainActor
struct TripGroupTests {
    static let body = """
    {"group":{"id":"g1","code":"K7M2PQ","host":true,"toLabel":"3 rue de la Pompe, Paris",
    "destination":{"lat":48.8637,"lon":2.2828},"maxMembers":5,"finishedAt":null,"ranking":null,
    "link":{"url":"https://api.lrda-mercuriale.uk/g/abc123","token":"abc123","observers":2},
    "me":{"id":"u1","sharing":true,"observable":true,"state":"driving","rank":null},
    "members":[
      {"id":"u1","name":"arthur","state":"driving","sharing":true,"online":true,"rank":null,
       "position":{"lat":45.75,"lon":4.83,"bearing":12.5},"speedKmh":112,"progress":0.35,
       "remainingM":248000,"etaAt":"2026-09-22T18:30:00.000Z","routeRev":1},
      {"id":"u2","name":"lea","state":"driving","sharing":false,"online":true,"rank":null}
    ]}}
    """

    /// The group out of an answer, nil for anything else.
    static func group(_ answer: GroupAnswer) -> TripGroup? {
        if case .group(let group) = answer { return group }
        return nil
    }

    @Test func readsTheGroupAndItsLink() async {
        let api = TripGroupAPI(client: backend(StubTransport(body: Self.body)))
        let group = Self.group(await api.mine(token: "t0k"))
        #expect(group?.code == "K7M2PQ")
        #expect(group?.isHost == true)
        #expect(group?.maxMembers == 5)
        #expect(group?.link?.observers == 2)
        #expect(group?.isOver == false)
        #expect(group?.members.count == 2)
    }

    @Test func aParticipantWhoDoesNotShareGivesNothing() async {
        let api = TripGroupAPI(client: backend(StubTransport(body: Self.body)))
        let group = Self.group(await api.mine(token: "t0k"))
        let lea = group?.members.first { $0.name == "lea" }
        #expect(lea?.sharing == false)
        #expect(lea?.position == nil)
        #expect(lea?.speedKmh == nil)
        #expect(lea?.detailLabel == "Ne partage pas sa position")

        let arthur = group?.members.first { $0.name == "arthur" }
        #expect(arthur?.speedKmh == 112)
        #expect(arthur?.position?.lat == 45.75)
        #expect(arthur?.bearing == 12.5)
    }

    @Test func aCancelledGroupIsSaidSo() async {
        let body = Self.body.replacingOccurrences(of: "\"finishedAt\":null", with: "\"finishedAt\":\"2026-09-22T18:00:00.000Z\",\"cancelled\":true")
        let api = TripGroupAPI(client: backend(StubTransport(body: body)))
        let group = Self.group(await api.mine(token: "t0k"))
        #expect(group?.isCancelled == true)
        #expect(group?.isLive == false)
    }

    @Test func noGroupAndNoAnswerAreTwoThings() async {
        let none = await TripGroupAPI(client: backend(StubTransport(body: #"{"group":null}"#))).mine(token: "t0k")
        let gone = await TripGroupAPI(client: backend(StubTransport(status: 404, body: #"{"error":"no group"}"#)))
            .update(position: nil, bearing: nil, speedKmh: nil, remainingMeters: nil, etaSeconds: nil, progress: nil, distanceMeters: nil, token: "t0k")
        let down = await TripGroupAPI(client: backend(StubTransport(status: 502, body: ""))).mine(token: "t0k")
        if case .gone = none {} else { Issue.record("null : pas de groupe") }
        if case .gone = gone {} else { Issue.record("404 : plus de groupe") }
        if case .failed = down {} else { Issue.record("502 : pas de réponse") }
    }

    @Test func theRankingJoinsTheTripInTheHistory() {
        let defaults = freshDefaults()
        let store = TripHistoryStore(defaults: defaults)
        let trip = TripRecord(
            id: "trip-1",
            startedAt: 1_758_000_000_000,
            fromLabel: "Ma position",
            toLabel: "3 rue de la Pompe, Paris",
            distanceMeters: 465_000,
            durationSeconds: 16_200,
            alertsCount: 3,
            topSpeedKmh: 131
        )
        store.add(trip)
        #expect(store.trips.first?.group == nil)

        store.attach(
            group: TripGroupResult(
                code: "K7M2PQ",
                myRank: 2,
                ranking: [
                    TripGroupRank(name: "lea", rank: 1, durationSeconds: 14_400, distanceMeters: 350_000, me: false),
                    TripGroupRank(name: "arthur", rank: 2, durationSeconds: 16_200, distanceMeters: 465_000, me: true),
                ]
            ),
            to: "trip-1"
        )
        #expect(store.trips.first?.group?.myRank == 2)
        #expect(store.trips.first?.group?.standingLabel == "2e sur 2")

        // It is written down: a new store, on the same defaults, still has the ranking.
        let again = TripHistoryStore(defaults: defaults)
        #expect(again.trips.first?.group?.ranking.count == 2)
        #expect(again.trips.first?.group?.ranking.first?.rankLabel == "1er")
    }
}
