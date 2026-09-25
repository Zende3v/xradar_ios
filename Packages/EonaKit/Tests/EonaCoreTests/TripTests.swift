import Foundation
import Testing
@testable import EonaCore

private let start = Date(timeIntervalSince1970: 1_789_000_000)

/// A fix [meters] east of the origin, [seconds] after the start.
private func fix(_ meters: Double, kmh: Double, at seconds: Int) -> LocationSample {
    LocationSample(
        latitude: 0,
        longitude: meters / 111_194.93,
        speedMps: kmh / 3.6,
        bearingDeg: 90,
        accuracyM: 5,
        timeMs: Int(start.timeIntervalSince1970 * 1000) + seconds * 1000
    )
}

private func alert(_ type: AlertType, id: String, meters: Int) -> RoadAlert {
    RoadAlert(type: type, title: "", roadLabel: nil, speedLimitKmh: nil, distanceMeters: meters, etaSeconds: 0, confidence: 1, lastReportedLabel: nil, id: id)
}

struct TripRecorderTests {
    @Test func stopsDistanceEventsAndEstimate() throws {
        var recorder = TripRecorder(toLabel: "Rennes", startedAt: start)
        recorder.plan(Route(points: [], distanceMeters: 2000, durationSeconds: 150, steps: []), now: start.addingTimeInterval(2))
        var meters = 0.0
        var second = 0
        func drive(_ seconds: Int, kmh: Double) {
            for _ in 0..<seconds {
                second += 1
                meters += kmh / 3.6
                recorder.add(fix(meters, kmh: kmh, at: second))
            }
        }
        drive(60, kmh: 36)
        drive(20, kmh: 0) // a red light
        drive(30, kmh: 36)
        drive(5, kmh: 0) // too short to be a stop
        drive(10, kmh: 36)
        drive(30, kmh: 0) // parked: still standing at the end

        recorder.meet([alert(.radarFixed, id: "r1", meters: 250), alert(.accident, id: "p1", meters: 600)])
        recorder.meet([alert(.radarFixed, id: "r1", meters: 40)])
        recorder.meet([alert(.accident, id: "p1", meters: 120)])

        let record = try #require(recorder.record(id: "t", now: start.addingTimeInterval(155)))
        #expect(record.toLabel == "Rennes")
        #expect(record.durationSeconds == 155)
        #expect(record.distanceMeters == 990) // the first fix has nothing before it
        #expect(record.topSpeedKmh == 36)
        #expect(record.stops == 1)
        #expect(record.stoppedSeconds == 20)
        #expect(record.plannedSeconds == 152)
        #expect(record.events == [.radarFixed: 1, .accident: 1])
        #expect(record.alertsCount == 2)
        #expect(record.averageSpeedKmh == 23)
        #expect(record.delayLabel == "À l'heure")
        #expect(record.stopsLabel == "1 arrêt · 20 s")

        #expect(TripRecorder(toLabel: "x", startedAt: start).record(id: "t", now: start.addingTimeInterval(30)) == nil)
    }

    @Test func aNewDestinationGetsANewEstimate() throws {
        var recorder = TripRecorder(toLabel: "A", startedAt: start)
        let route = Route(points: [], distanceMeters: 1000, durationSeconds: 100, steps: [])
        recorder.plan(route, now: start)
        recorder.plan(route, now: start.addingTimeInterval(50)) // a recalculation: same estimate
        recorder.retarget("B")
        recorder.plan(route, now: start.addingTimeInterval(60))
        #expect(recorder.toLabel == "B")
        for second in 1...70 {
            recorder.add(fix(Double(second) * 10, kmh: 36, at: second))
        }
        let record = try #require(recorder.record(id: "t", now: start.addingTimeInterval(200)))
        #expect(record.plannedSeconds == 160)
        #expect(record.delayLabel == "À l'heure") // 40 s late
        #expect(record.measure?.retargeted == true)
    }
}

/// Epoch millis [seconds] after the start.
private func millis(_ seconds: Int) -> Int {
    Int(start.timeIntervalSince1970 * 1000) + seconds * 1000
}

struct TripMeasureTests {
    @Test func longStopsArePausesOnlyOnARoadKnownClear() throws {
        var recorder = TripRecorder(toLabel: "Rennes", startedAt: start)
        var meters = 0.0
        var second = 0
        var asked = 0
        func drive(_ seconds: Int, kmh: Double, traffic: StopTraffic = .unknown) {
            for _ in 0..<seconds {
                second += 1
                meters += kmh / 3.6
                recorder.add(fix(meters, kmh: kmh, at: second)) {
                    asked += 1
                    return traffic
                }
            }
        }
        drive(60, kmh: 36)
        #expect(asked == 0) // the traffic is asked only while standing still
        drive(300, kmh: 0, traffic: .clear) // five minutes on a road known clear: a pause
        drive(10, kmh: 36)
        drive(299, kmh: 0, traffic: .clear) // a second short of it: a stop, no pause
        drive(10, kmh: 36)
        drive(150, kmh: 0, traffic: .clear)
        drive(150, kmh: 0, traffic: .jam) // in a jam for part of it: the drive itself
        drive(10, kmh: 36)
        drive(200, kmh: 0, traffic: .clear)
        drive(100, kmh: 0, traffic: .unknown) // the traffic not known all along: uncertain
        drive(10, kmh: 36)
        drive(400, kmh: 0, traffic: .clear) // parked at the destination: nothing
        #expect(asked == 1_599)

        let record = try #require(recorder.record(id: "t", arrived: true, now: start.addingTimeInterval(1_700)))
        let measure = try #require(record.measure)
        #expect(measure.pausedSeconds == 300)
        #expect(measure.uncertainSeconds == 300)
        #expect(measure.arrived)
        // The stops themselves keep their meaning.
        #expect(record.stops == 4)
        #expect(record.stoppedSeconds == 1_199)
    }

    @Test func etaShownAtTheDepartureThenOnceAt25_50And75Percent() throws {
        var recorder = TripRecorder(toLabel: "Nantes", appVersion: "1.0.0 (1)", startedAt: start)
        var meters = 0.0
        var second = 0
        func drive(_ seconds: Int, kmh: Double, traffic: StopTraffic = .clear) {
            for _ in 0..<seconds {
                second += 1
                meters += kmh / 3.6
                recorder.add(fix(meters, kmh: kmh, at: second)) { traffic }
            }
        }
        func at(_ seconds: Int) -> Date {
            start.addingTimeInterval(Double(seconds))
        }
        let first = Route(points: [], distanceMeters: 1_000, durationSeconds: 100, engine: "ors", mapVersion: "2026-09-20")
        recorder.follow(first)
        drive(20, kmh: 36) // to the route: 190 m before the departure
        recorder.checkpoint(route: first, remainingShare: 1, now: at(20))
        #expect(!recorder.awaitsCheckpoint) // not departed: nothing kept
        recorder.depart(route: first, remainingShare: 1, manualStart: false, now: at(20))
        recorder.depart(route: first, remainingShare: 0.5, manualStart: true, now: at(21)) // once per trip
        #expect(recorder.departedAt == millis(20))
        #expect(recorder.plannedMeters == 1_000)

        drive(24, kmh: 36) // 240 m since the departure: 24 % of the way
        recorder.checkpoint(route: first, remainingShare: 0.76, now: at(44))
        drive(2, kmh: 36) // 260 m: past a quarter
        recorder.checkpoint(route: first, remainingShare: 0.74, now: at(46))
        recorder.checkpoint(route: first, remainingShare: 0.70, now: at(46)) // never twice
        drive(300, kmh: 0) // a coffee break on a road known clear
        drive(1, kmh: 36)
        // A recalculation: the new route (its engine unsaid) starts whole.
        let detour = Route(points: [], distanceMeters: 2_000, durationSeconds: 150)
        recorder.follow(detour)
        recorder.recalculated()
        recorder.checkpoint(route: detour, remainingShare: 1, now: at(347)) // 270 / 2 270 m
        drive(28, kmh: 36) // 550 m since the departure
        recorder.checkpoint(route: detour, remainingShare: 0.25, now: at(375)) // 550 / 1 050 m
        // Standing still when the 75 % comes: that stop is not counted before it.
        drive(400, kmh: 0, traffic: .unknown)
        recorder.checkpoint(route: detour, remainingShare: 0.06, now: at(775)) // 550 / 670 m
        #expect(!recorder.awaitsCheckpoint)
        drive(1, kmh: 36)
        recorder.follow(Route(points: [], distanceMeters: 100, durationSeconds: 10, engine: "ors"))
        recorder.tookFaster()
        recorder.sawTraffic(["tomtom"])
        recorder.sawTraffic(["crowd", "tomtom"])

        let record = try #require(recorder.record(id: "t", arrived: true, now: at(800)))
        let measure = try #require(record.measure)
        #expect(measure.etaChecks == [
            EtaCheck(at: 0, shownAt: millis(20), arrivalAt: millis(20) + 100_000, pausedBefore: 0, uncertainBefore: 0),
            EtaCheck(at: 25, shownAt: millis(46), arrivalAt: millis(46) + 74_000, pausedBefore: 0, uncertainBefore: 0),
            // 150 s × 0.25 = 37.5 s: rounded up, as Android does.
            EtaCheck(at: 50, shownAt: millis(375), arrivalAt: millis(375) + 38_000, pausedBefore: 300, uncertainBefore: 0),
            EtaCheck(at: 75, shownAt: millis(775), arrivalAt: millis(775) + 9_000, pausedBefore: 300, uncertainBefore: 0),
        ])
        #expect(measure.arrived)
        #expect(measure.departedAt == millis(20))
        #expect(!measure.manualStart)
        #expect(measure.plannedMeters == 1_000)
        #expect(measure.mapVersion == "2026-09-20")
        #expect(measure.pausedSeconds == 300)
        #expect(measure.uncertainSeconds == 400)
        #expect(measure.recalcCount == 1)
        #expect(measure.fasterCount == 1)
        #expect(measure.engines == ["ors", "unknown"])
        #expect(measure.trafficSources == ["tomtom", "crowd"])
        #expect(measure.appVersion == "1.0.0 (1)")
        #expect(measure.platform == "ios")
        #expect(measure.etaMode == "proportional")
    }

    @Test func aTripStartedByHandOrStoppedOnTheWay() throws {
        var recorder = TripRecorder(toLabel: "Brest", startedAt: start)
        // A simulated start departs at its first fix, before any route is known.
        recorder.depart(route: nil, remainingShare: 1, manualStart: true, now: start)
        // The route comes later: no 0 % checkpoint made up after the departure.
        recorder.checkpoint(route: Route(points: [], distanceMeters: 1_000, durationSeconds: 100), remainingShare: 1, now: start.addingTimeInterval(1))
        #expect(recorder.awaitsCheckpoint)
        for second in 1...70 {
            recorder.add(fix(Double(second) * 10, kmh: 36, at: second))
        }
        let measure = try #require(recorder.record(id: "t", now: start.addingTimeInterval(70))?.measure)
        #expect(!measure.arrived)
        #expect(measure.manualStart)
        #expect(measure.departedAt == millis(0))
        #expect(measure.plannedMeters == nil)
        #expect(measure.mapVersion == nil)
        #expect(measure.etaChecks.isEmpty)
        #expect(measure.engines.isEmpty)

        // Never on the route: no departure at all.
        var idle = TripRecorder(toLabel: "Brest", startedAt: start)
        for second in 1...70 {
            idle.add(fix(Double(second) * 10, kmh: 36, at: second))
        }
        let never = try #require(idle.record(id: "t", now: start.addingTimeInterval(70))?.measure)
        #expect(never.departedAt == nil)
        #expect(!never.manualStart)
    }

    @Test func trafficSourcesOfARoute() {
        let traffic = RouteTraffic(totalMeters: 1_000, stretches: [
            TrafficStretch(fromMeters: 0, toMeters: 100, level: .slow),
            TrafficStretch(fromMeters: 200, toMeters: 300, level: .jam, delaySeconds: 60, source: "crowd"),
            TrafficStretch(fromMeters: 400, toMeters: 500, level: .heavy),
        ])
        #expect(traffic.sources == ["tomtom", "crowd"])
        #expect(RouteTraffic(totalMeters: 1_000, stretches: []).sources.isEmpty)
    }
}

struct TripRecordLabelTests {
    func trip(seconds: Int, planned: Int?, stops: Int = 0, stopped: Int = 0) -> TripRecord {
        TripRecord(
            id: "t", startedAt: 0, fromLabel: "", toLabel: "", distanceMeters: 30_000, durationSeconds: seconds,
            alertsCount: 0, topSpeedKmh: 90, plannedSeconds: planned, stops: stops, stoppedSeconds: stopped
        )
    }

    @Test func realTimeAgainstTheEstimate() {
        let late = trip(seconds: 45 * 60, planned: 41 * 60, stops: 3, stopped: 130)
        #expect(late.plannedLabel == "41 min")
        #expect(late.delayLabel == "+4 min")
        #expect(late.averageSpeedKmh == 40)
        #expect(late.stopsLabel == "3 arrêts · 2 min")
        #expect(trip(seconds: 3900, planned: 4200).delayLabel == "−5 min")
        #expect(trip(seconds: 7300, planned: 3000).delayLabel == "+1 h 11")
        let unknown = trip(seconds: 600, planned: nil)
        #expect(unknown.plannedLabel == nil)
        #expect(unknown.delayLabel == nil)
        #expect(unknown.stopsLabel == "Aucun")
    }

    @Test func eventKindsHaveStableNames() {
        for type in AlertType.allCases {
            #expect(AlertType(wireName: type.wireName) == type)
        }
        #expect(AlertType(wireName: "nope") == nil)
    }
}
