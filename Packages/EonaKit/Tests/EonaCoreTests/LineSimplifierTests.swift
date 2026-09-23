import Foundation
import Testing
@testable import EonaCore

/// Another member's route, made light for the map: under budget, ends kept, shape kept.
struct LineSimplifierTests {
    /// A 400 km zigzag of 8000 points, every 50 m, swinging 2 km either side.
    static let longRoute: [GeoPoint] = (0..<8000).map { i in
        GeoPoint(lat: 45.0 + Double(i) * 0.00045, lon: 4.8 + sin(Double(i) / 200) * 0.025)
    }

    @Test func aLongRouteFitsTheBudget() {
        let light = LineSimplifier.simplify(Self.longRoute, maxPoints: 600)
        #expect(light.count <= 600)
        #expect(light.first == Self.longRoute.first)
        #expect(light.last == Self.longRoute.last)
    }

    @Test func theShapeStaysWithinAFewDozenMetres() {
        let light = LineSimplifier.simplify(Self.longRoute, maxPoints: 600)
        let path = RoutePath(points: light)
        // Every original point still lies close to the light line.
        let worst = Self.longRoute.enumerated()
            .filter { $0.offset % 40 == 0 }
            .compactMap { path.match(lat: $0.element.lat, lon: $0.element.lon)?.offRouteMeters }
            .max() ?? .infinity
        #expect(worst < 60)
    }

    @Test func aShortRouteIsLeftAlone() {
        let short = Array(Self.longRoute.prefix(300))
        #expect(LineSimplifier.simplify(short, maxPoints: 600) == short)
    }
}
