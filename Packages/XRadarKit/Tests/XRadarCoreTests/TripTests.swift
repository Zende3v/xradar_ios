import Foundation
import Testing
@testable import XRadarCore

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
