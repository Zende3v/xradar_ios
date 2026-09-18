import Foundation
import Testing
@testable import XRadarCore

/// A fix [second] seconds in, going north at [kmh] from (48, 2).
private func fix(_ second: Int, kmh: Double, accuracy: Double = 5, bearing: Double? = 0, start: Double = 0) -> LocationSample {
    let meters = start + kmh / 3.6 * Double(second)
    return LocationSample(latitude: 48 + meters / 111_320, longitude: 2, speedMps: kmh / 3.6, bearingDeg: bearing, accuracyM: accuracy, timeMs: second * 1000)
}

private func drive(
    _ detector: inout SlowdownDetector,
    seconds: ClosedRange<Int>,
    kmh: Double,
    limit: Int? = 110,
    fromRoad: Bool = true,
    paused: Bool = false,
    accuracy: Double = 5
) -> [Int: Slowdown] {
    var found: [Int: Slowdown] = [:]
    for second in seconds {
        if let slowdown = detector.update(
            sample: fix(second, kmh: kmh, accuracy: accuracy),
            speedKmh: Int(kmh),
            limitKmh: limit,
            limitFromRoad: fromRoad,
            paused: paused
        ) {
            found[second] = slowdown
        }
    }
    return found
}

struct SlowdownDetectorTests {
    @Test func aLongCrawlOnAFastRoadIsASlowdown() throws {
        var detector = SlowdownDetector()
        let found = drive(&detector, seconds: 0...120, kmh: 20)
        #expect(found.count == 1)
        let (second, slowdown) = try #require(found.first)
        #expect((85...90).contains(second))
        #expect(slowdown.speedKmh == 20)
        #expect(slowdown.limitKmh == 110)
        #expect(slowdown.bearingDeg == 0)
    }

    @Test func notOnTownRoadsNorForARadarsLimitNorParkedNorWhenFastEnough() {
        var town = SlowdownDetector()
        #expect(drive(&town, seconds: 0...200, kmh: 10, limit: 50).isEmpty)
        var radar = SlowdownDetector()
        #expect(drive(&radar, seconds: 0...200, kmh: 20, fromRoad: false).isEmpty)
        var parked = SlowdownDetector()
        #expect(drive(&parked, seconds: 0...200, kmh: 0).isEmpty)
        var fast = SlowdownDetector()
        #expect(drive(&fast, seconds: 0...200, kmh: 60).isEmpty)
        var noLimit = SlowdownDetector()
        #expect(drive(&noLimit, seconds: 0...200, kmh: 20, limit: nil).isEmpty)
        var blurry = SlowdownDetector()
        #expect(drive(&blurry, seconds: 0...200, kmh: 20, accuracy: 80).isEmpty)
    }

    @Test func aShortSlowdownOrTheTripsEndsDoNotCount() {
        var detector = SlowdownDetector()
        // 60 s of crawl, then normal speed: nothing.
        #expect(drive(&detector, seconds: 0...60, kmh: 20).isEmpty)
        #expect(drive(&detector, seconds: 61...200, kmh: 100).isEmpty)
        var near = SlowdownDetector()
        #expect(drive(&near, seconds: 0...200, kmh: 20, paused: true).isEmpty)
    }

    @Test func onceThenQuietForFiveMinutes() {
        var detector = SlowdownDetector()
        let found = drive(&detector, seconds: 0...700, kmh: 20)
        let seconds = found.keys.sorted()
        #expect(seconds.count == 2)
        #expect(seconds[1] - seconds[0] >= 300)
    }
}
