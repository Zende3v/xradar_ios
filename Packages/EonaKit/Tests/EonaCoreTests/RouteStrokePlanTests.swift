import Foundation
import Testing
@testable import EonaCore
#if canImport(MapKit)
import MapKit
#endif

struct RouteStrokePlanTests {
    private func points(_ count: Int) -> [GeoPoint] {
        (0..<count).map { GeoPoint(lat: 48.85 + sin(Double($0) / 100) * 0.001,
                                  lon: 2.35 + Double($0) * 0.0002) }
    }

    @Test func keepsEverySegmentOnLongRoute() throws {
        let points = self.points(40_001)
        let plan = RouteStrokePlan(points: points)
        #expect(plan.totalMeters > 500_000)
        #expect(plan.chunks.count > 300)
        #expect(plan.chunks.first?.firstPoint == 0)
        #expect(plan.chunks.last?.lastPoint == points.count - 1)
        #expect(plan.chunks.reduce(0) { $0 + $1.lastPoint - $1.firstPoint } == points.count - 1)
        for index in plan.chunks.indices.dropFirst() {
            #expect(plan.chunks[index - 1].lastPoint == plan.chunks[index].firstPoint)
            #expect(plan.chunks[index - 1].endFraction == plan.chunks[index].startFraction)
        }
        #expect(plan.chunks.last?.endFraction == 1)
    }

    @Test func cutsContinuouslyBelowOneMeter() throws {
        let plan = RouteStrokePlan(points: points(1_001))
        let first = plan.fraction(atMeters: 10)
        let next = plan.fraction(atMeters: 10.1)
        #expect(next > first)
        let chunk = try #require(plan.chunks.first)
        #expect(chunk.localFraction(next) > chunk.localFraction(first))
        #expect(plan.fraction(atMeters: -5) == 0)
        #expect(plan.fraction(atMeters: plan.totalMeters + 5) == 1)
    }

    @Test func updatesOnlyPortionsCrossedByCursor() throws {
        let plan = RouteStrokePlan(points: points(40_001))
        let chunk = plan.chunks[150]
        let middle = (chunk.startFraction + chunk.endFraction) / 2
        #expect(plan.affectedChunks(from: middle, to: middle + 0.000001) == (150...150))
        let boundary = chunk.endFraction
        #expect(plan.affectedChunks(from: boundary - 0.000001, to: boundary + 0.000001) == (150...151))
        #expect(plan.affectedChunks(from: middle, to: middle) == nil)
    }

    @Test func restoresRouteAfterLeavingItAndSupportsReverseMovement() throws {
        let plan = RouteStrokePlan(points: points(1_001))
        #expect(plan.affectedChunks(from: 1, to: 0) == (0...(plan.chunks.count - 1)))
        #expect(plan.affectedChunks(from: 0.7, to: 0.2) == plan.affectedChunks(from: 0.2, to: 0.7))
        for chunk in plan.chunks {
            #expect(chunk.localFraction(0) == 0)
            #expect(chunk.localFraction(1) == 1)
            #expect(chunk.localFraction(chunk.startFraction) == 0)
            #expect(abs(chunk.localFraction(chunk.endFraction) - 1) < 1e-12)
        }
    }

    @Test func ignoresZeroLengthGeometryWithoutDivisionByZero() {
        for points in [[], [GeoPoint(lat: 48, lon: 2)], Array(repeating: GeoPoint(lat: 48, lon: 2), count: 300)] {
            let plan = RouteStrokePlan(points: points)
            #expect(plan.chunks.isEmpty)
            #expect(plan.totalMeters == 0)
            #expect(plan.fraction(atMeters: 10) == 0)
            #expect(plan.affectedChunks(from: 0, to: 1) == nil)
        }
    }

    @Test func matchesNavigationDistancesAcrossLatitudeChanges() {
        let points = [GeoPoint(lat: 43, lon: 1), GeoPoint(lat: 48, lon: 2), GeoPoint(lat: 51, lon: 3)]
        let path = RoutePath(points: points)
        let plan = RouteStrokePlan(points: points, segmentsPerChunk: 1)
        #expect(abs(path.totalMeters - plan.totalMeters) < 1e-9)
        let firstMeters = Geo.haversine(lat1: 43, lon1: 1, lat2: 48, lon2: 2)
        #expect(abs(plan.fraction(atMeters: firstMeters) - plan.chunks[0].endFraction) < 1e-12)
    }

    @Test func keepsSmoothingStableAtThirtyAndSixtyFrames() {
        func response(frames: Int) -> Double {
            var position = 0.0
            let seconds = 0.1 / Double(frames)
            for _ in 0..<frames {
                position += (1 - position) * FrameInterpolation.factor(reference: 0.12, seconds: seconds)
            }
            return position
        }
        #expect(abs(response(frames: 3) - response(frames: 6)) < 1e-12)
        #expect(FrameInterpolation.factor(reference: 0.12, seconds: 0) == 0)
    }

    #if canImport(MapKit)
    @Test @MainActor func followsMapKitNativeStrokeUnits() {
        let points = self.points(513)
        let plan = RouteStrokePlan(points: points)
        let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
        for chunk in plan.chunks {
            #expect(abs(Double(line.location(atPointIndex: chunk.firstPoint)) - chunk.startFraction) < 0.00001)
            #expect(abs(Double(line.location(atPointIndex: chunk.lastPoint)) - chunk.endFraction) < 0.00001)
        }
    }
    #endif
}
