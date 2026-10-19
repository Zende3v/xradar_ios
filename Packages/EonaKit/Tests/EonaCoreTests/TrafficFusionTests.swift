import Foundation
import Testing
@testable import EonaCore

/// Fusion des retards superposés (contrat 20/10, mêmes cas que backend).
struct TrafficFusionTests {
    private func here(_ from: Double, _ to: Double, _ delay: Int?) -> TrafficStretch {
        TrafficStretch(fromMeters: from, toMeters: to, level: .jam, delaySeconds: delay, source: TrafficStretch.here)
    }

    private func crowd(_ from: Double, _ to: Double, _ delay: Int?, level: TrafficLevel = .jam) -> TrafficStretch {
        TrafficStretch(fromMeters: from, toMeters: to, level: level, delaySeconds: delay, source: TrafficStretch.crowd)
    }

    private func closure(_ from: Double, _ to: Double, _ delay: Int?) -> TrafficStretch {
        TrafficStretch(fromMeters: from, toMeters: to, level: .closed, delaySeconds: delay, source: TrafficStretch.datagouv, kind: "closed")
    }

    private func total(_ stretches: [TrafficStretch]) -> Int {
        stretches.reduce(0) { $0 + ($1.delaySeconds ?? 0) }
    }

    @Test func overlappingObservationsCountOnceBeyondHere() {
        // Cas 1 : HERE 100 s, signalement 180 s, vitesses 140 s, même portion : 180, complément 80.
        let known = [here(0, 500, 100)]
        let added = TrafficParts.extra(over: known, zones: [crowd(0, 500, 180), crowd(0, 500, 140)], keepFree: false)
        #expect(added == [crowd(0, 500, 80)])
        #expect(total(known + added) == 180)
        var parts = TrafficParts(routeMeters: 1_000)
        parts.tomtom = known
        parts.crowd = [crowd(0, 500, 140), crowd(0, 500, 180)]
        #expect(total(parts.merged().stretches) == 180)
    }

    @Test func orderAndDuplicatesChangeNothing() {
        // Cas 2 : sans HERE, 180 ; doublons et ordre inversé sans effet.
        let a = crowd(0, 500, 180)
        let b = crowd(0, 500, 140)
        let once = TrafficParts.extra(over: [], zones: [a, b], keepFree: false)
        #expect(total(once) == 180)
        #expect(TrafficParts.extra(over: [], zones: [b, a], keepFree: false) == once)
        #expect(TrafficParts.extra(over: [], zones: [b, a, b, a, a], keepFree: false) == once)
    }

    @Test func disjointZonesAdd() {
        // Cas 3.
        let added = TrafficParts.extra(over: [], zones: [crowd(0, 500, 180), crowd(500, 1_000, 140)], keepFree: false)
        #expect(total(added) == 320)
    }

    @Test func partlyOverlappingZonesTakeTheWorstPerPortion() {
        // Cas 4 : 0–1000/100 et 500–1500/100 : 150, jamais maximum global ni somme.
        let added = TrafficParts.extra(over: [], zones: [crowd(500, 1_500, 100), crowd(0, 1_000, 100)], keepFree: false)
        #expect(total(added) == 150)
        #expect(added == [crowd(0, 1_000, 100), crowd(1_000, 1_500, 50)])
    }

    @Test func complementStaysOnItsOwnPortion() {
        // Cas 5 : HERE couvre 0–500 ; complément 50 seulement sur 500–1000.
        let added = TrafficParts.extra(over: [here(0, 500, 100)], zones: [crowd(0, 1_000, 100)], keepFree: false)
        #expect(added == [crowd(500, 1_000, 50)])
        // Cas 6 : HERE plus lent partout : rien.
        #expect(TrafficParts.extra(over: [here(0, 1_000, 200)], zones: [crowd(0, 500, 100)], keepFree: false).isEmpty)
    }

    @Test func fragmentingNeverInflatesNorLosesTime() {
        // Cas 7 : zones dominées découpent la portion ; total inchangé.
        let main = crowd(0, 1_000, 3)
        let dominated = (0...60).map { crowd(Double($0 * 10), Double($0 * 10 + 400), 1) }
        let alone = TrafficParts.extra(over: [], zones: [main], keepFree: false)
        #expect(TrafficParts.extra(over: [], zones: dominated + [main], keepFree: false) == alone)
        #expect(total(alone) == 3)
        // Petits compléments par zone : 0,4 s × 10 = 4 (arrondi par zone : 0) ; 0,6 s × 10 = 6 (sinon 10).
        let tenths = (0..<10).map { crowd(Double($0 * 100), Double($0 * 100 + 100), 1) }
        #expect(total(TrafficParts.extra(over: [here(0, 1_000, 6)], zones: tenths, keepFree: false)) == 4)
        #expect(total(TrafficParts.extra(over: [here(0, 1_000, 4)], zones: tenths, keepFree: false)) == 6)
    }

    @Test func closuresStayVisibleAndSwitchedOffSourcesAddNothing() {
        // Cas 8 : fermeture publique à 0 s conservée, avec ou sans keepFree ; couverte par HERE, visible à 0 s.
        for keepFree in [true, false] {
            #expect(TrafficParts.extra(over: [], zones: [closure(100, 200, 0)], keepFree: keepFree) == [closure(100, 200, 0)])
            #expect(TrafficParts.extra(over: [here(0, 1_000, 500)], zones: [closure(0, 1_000, 100)], keepFree: keepFree) == [closure(0, 1_000, 0)])
            // Couverte en partie : marqueur entier à 0 s, plus complément sur sa seule portion.
            #expect(TrafficParts.extra(over: [here(0, 500, 100)], zones: [closure(0, 1_000, 100)], keepFree: keepFree)
                == [closure(0, 1_000, 0), closure(500, 1_000, 50)])
            // Même fermeture, retards différents : un seul marqueur.
            #expect(TrafficParts.extra(over: [], zones: [closure(100, 200, 50), closure(100, 200, 0)], keepFree: keepFree)
                == [closure(100, 200, 0), closure(100, 200, 50)])
        }
        var parts = TrafficParts(routeMeters: 1_000)
        parts.tomtom = [here(0, 500, 100)]
        parts.travelSeconds = 300
        parts.crowd = [crowd(0, 500, 180)]
        parts.datagouv = [
            closure(600, 700, 0),
            TrafficStretch(fromMeters: 800, toMeters: 900, level: .slow, delaySeconds: 30, source: TrafficStretch.datagouv, kind: "works"),
        ]
        #expect(parts.merged(withDatagouv: true).stretches.contains(closure(600, 700, 0)))
        #expect(total(parts.merged(withDatagouv: true).stretches) == 210)
        var without = parts
        without.datagouv = []
        #expect(parts.merged(withDatagouv: false) == without.merged(withDatagouv: true))
        without.crowd = []
        #expect(without.merged().stretches == [here(0, 500, 100)])
    }

    @Test func invalidStretchesAddNoTime() {
        // Cas 9 : bornes égales, inversées, non finies, retard négatif ou absent.
        let invalid = [
            crowd(100, 100, 50), crowd(500, 100, 50), crowd(.nan, 100, 50), crowd(0, .infinity, 50),
            crowd(-.infinity, .infinity, 50), crowd(0, 500, -30), crowd(0, 500, nil), crowd(0, 500, 0),
        ]
        #expect(TrafficParts.extra(over: [], zones: invalid, keepFree: false).isEmpty)
        #expect(TrafficParts.extra(over: [], zones: invalid, keepFree: true).allSatisfy { ($0.delaySeconds ?? 0) == 0 })
        // Connus invalides ignorés : rien soustrait.
        let badKnown = [here(0, 0, 100), here(.nan, 500, 100), here(0, 500, -100), here(0, .infinity, 100)]
        #expect(TrafficParts.extra(over: badKnown, zones: [crowd(0, 500, 100)], keepFree: false) == [crowd(0, 500, 100)])
        #expect(TrafficParts.extra(over: [], zones: [], keepFree: true).isEmpty)
    }

    @Test func markersFollowTheSharedContract() {
        // Sans retard (nil ou zéro) : marqueur à 0 s avec keepFree seulement.
        let works = TrafficStretch(fromMeters: 800, toMeters: 900, level: .slow, delaySeconds: nil, source: TrafficStretch.datagouv, kind: "works")
        let free = works.moved(from: 800, to: 900, delay: 0)
        #expect(TrafficParts.extra(over: [], zones: [works], keepFree: true) == [free])
        #expect(TrafficParts.extra(over: [], zones: [free], keepFree: true) == [free])
        #expect(TrafficParts.extra(over: [], zones: [works, free], keepFree: false).isEmpty)
        // Retard négatif hors fermeture : aucun marqueur libre.
        #expect(TrafficParts.extra(over: [], zones: [crowd(0, 500, -30)], keepFree: true).isEmpty)
        for keepFree in [true, false] {
            // Fermeture inversée rejetée, jamais retournée 100–500.
            #expect(TrafficParts.extra(over: [], zones: [closure(500, 100, 0)], keepFree: keepFree).isEmpty)
            #expect(TrafficParts.extra(over: [], zones: [closure(500, 100, 100)], keepFree: keepFree).isEmpty)
            // Point admis ; bornes non finies rejetées.
            #expect(TrafficParts.extra(over: [], zones: [closure(300, 300, 0)], keepFree: keepFree) == [closure(300, 300, 0)])
            #expect(TrafficParts.extra(over: [], zones: [closure(0, .infinity, 0), closure(.nan, 100, 0)], keepFree: keepFree).isEmpty)
        }
    }

    @Test func infiniteDensityAddsNoTime() {
        // Largeur sous-normale finie, densité 1 / 1e-320 infinie : aucun temps, rien soustrait.
        let tiny = 1e-320
        #expect(tiny > 0 && tiny < Double.leastNormalMagnitude && (1 / tiny).isInfinite)
        #expect(TrafficParts.extra(over: [], zones: [crowd(0, tiny, 1)], keepFree: false).isEmpty)
        #expect(TrafficParts.extra(over: [], zones: [crowd(0, tiny, 1)], keepFree: true).isEmpty)
        #expect(TrafficParts.extra(over: [here(0, tiny, 1)], zones: [crowd(0, 500, 100)], keepFree: false) == [crowd(0, 500, 100)])
    }

    @Test func equalDensityPrefersEarlierEnd() {
        // Même début, même densité : fin croissante avant retard, source et nature.
        // Source et nature favoriseraient la longue ; la courte domine 0–500, la longue 500–1000.
        let speed = TrafficStretch(fromMeters: 0, toMeters: 500, level: .slow, delaySeconds: 50, source: TrafficStretch.datagouv, kind: "speed")
        let report = TrafficStretch(fromMeters: 0, toMeters: 1_000, level: .slow, delaySeconds: 100, source: TrafficStretch.crowd, kind: "report")
        let expected = [speed, report.moved(from: 500, to: 1_000, delay: 50)]
        #expect(TrafficParts.extra(over: [], zones: [speed, report], keepFree: false) == expected)
        #expect(TrafficParts.extra(over: [], zones: [report, speed], keepFree: false) == expected)
        #expect(TrafficParts.extra(over: [], zones: [report, speed], keepFree: true) == expected)
    }

    @Test func remainingEtaDropsThePassedComplement() {
        // Cas 10 : route 1 km, HERE 300 s dont 100 s listés sur 0–500 ; base 200 s.
        let route = Route(points: [GeoPoint(lat: 0, lon: 0), GeoPoint(lat: 0, lon: 1)], distanceMeters: 1_000, durationSeconds: 120)
        var parts = TrafficParts(routeMeters: 1_000)
        parts.tomtom = [here(0, 500, 100)]
        parts.travelSeconds = 300
        parts.crowd = [crowd(0, 500, 180), crowd(0, 500, 140)]
        let jam = parts.merged()
        func left(_ along: Double, _ traffic: RouteTraffic) -> Double {
            EtaEstimator.secondsLeft(route: route, routeMeters: 1_000, alongMeters: along, traffic: traffic)
        }
        // HERE compté une fois, complément 80 en plus.
        #expect(abs(left(0, jam) - 380) < 0.001)
        // Portion passée : complément et retard HERE disparus.
        #expect(abs(left(600, jam) - 80) < 0.001)
        // Complément posé sur 500–1000 seulement : intact à 500, au prorata ensuite.
        parts.crowd = [crowd(0, 1_000, 100)]
        let later = parts.merged()
        #expect(abs(left(0, later) - 350) < 0.001)
        #expect(abs(left(500, later) - (100 + 50)) < 0.001)
        #expect(abs(left(750, later) - (50 + 25)) < 0.001)
        #expect(left(1_000, later) == 0)
    }
}
