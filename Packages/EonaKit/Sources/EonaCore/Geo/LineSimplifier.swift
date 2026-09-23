import Foundation

/// A long line made light enough to draw fast, with the least visible change: points that sit
/// within a few metres of the line through their neighbours go (Douglas–Peucker, in local metres).
/// The tolerance grows only as much as needed to stay under a point budget, so a short trip keeps
/// every curve and a 500 km one keeps its shape at every zoom the map will show.
public enum LineSimplifier {
    /// [points] with at most [maxPoints] of them; the first and the last are always kept.
    public static func simplify(_ points: [GeoPoint], maxPoints: Int, startToleranceMeters: Double = 8) -> [GeoPoint] {
        guard points.count > max(maxPoints, 2) else { return points }
        // Local metres around the line's middle: good enough for a few hundred kilometres.
        let middle = points[points.count / 2]
        let metersPerLat = 111_320.0
        let metersPerLon = 111_320.0 * max(cos(Geo.radians(middle.lat)), 0.1)
        let xs = points.map { $0.lon * metersPerLon }
        let ys = points.map { $0.lat * metersPerLat }

        var tolerance = startToleranceMeters
        var kept = points
        for _ in 0..<12 {
            let keep = douglasPeucker(xs: xs, ys: ys, tolerance: tolerance)
            kept = points.indices.filter { keep[$0] }.map { points[$0] }
            if kept.count <= maxPoints { return kept }
            tolerance *= 1.6
        }
        return kept
    }

    private static func douglasPeucker(xs: [Double], ys: [Double], tolerance: Double) -> [Bool] {
        var keep = [Bool](repeating: false, count: xs.count)
        keep[0] = true
        keep[xs.count - 1] = true
        var stack = [(0, xs.count - 1)]
        while let (first, last) = stack.popLast() {
            let ax = xs[first], ay = ys[first]
            let dx = xs[last] - ax, dy = ys[last] - ay
            let length2 = dx * dx + dy * dy
            var worst = 0.0
            var index = -1
            if last - first > 1 {
                for i in (first + 1)..<last {
                    let t = length2 == 0 ? 0 : min(max(((xs[i] - ax) * dx + (ys[i] - ay) * dy) / length2, 0), 1)
                    let ex = xs[i] - (ax + t * dx)
                    let ey = ys[i] - (ay + t * dy)
                    let distance = (ex * ex + ey * ey).squareRoot()
                    if distance > worst {
                        worst = distance
                        index = i
                    }
                }
            }
            if index > 0, worst > tolerance {
                keep[index] = true
                stack.append((first, index))
                stack.append((index, last))
            }
        }
        return keep
    }
}
