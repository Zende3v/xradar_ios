import Foundation

/// Géométrie complète. Découpage du rendu, aucun point supprimé.
public struct RouteStrokePlan: Sendable {
    public struct Chunk: Sendable, Hashable {
        public let firstPoint: Int
        public let lastPoint: Int
        public let startFraction: Double
        public let endFraction: Double

        public func localFraction(_ fraction: Double) -> Double {
            let length = endFraction - startFraction
            guard length > 0 else { return fraction >= endFraction ? 1 : 0 }
            return min(max((fraction - startFraction) / length, 0), 1)
        }
    }

    public let chunks: [Chunk]
    public let totalMeters: Double
    private let meters: [Double]
    private let lengths: [Double]

    public init(points: [GeoPoint], segmentsPerChunk: Int = 128) {
        var meters = [0.0]
        var lengths = [0.0]
        if points.count >= 2 {
            for i in 1..<points.count {
                let a = points[i - 1]
                let b = points[i]
                meters.append(meters[i - 1] + Geo.haversine(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon))
                let dx = (b.lon - a.lon) * .pi / 180
                let dy = Self.mercatorY(b.lat) - Self.mercatorY(a.lat)
                lengths.append(lengths[i - 1] + hypot(dx, dy))
            }
        }
        self.meters = meters
        self.lengths = lengths
        totalMeters = meters.last ?? 0
        let total = lengths.last ?? 0
        var chunks: [Chunk] = []
        if points.count >= 2, total > 0 {
            let batch = max(segmentsPerChunk, 1)
            var first = 0
            while first < points.count - 1 {
                let last = first + min(batch, points.count - 1 - first)
                // Segments nuls conservés dans géométrie ; aucun trait à dessiner.
                if lengths[last] > lengths[first] {
                    chunks.append(Chunk(firstPoint: first, lastPoint: last,
                                        startFraction: lengths[first] / total, endFraction: lengths[last] / total))
                }
                first = last
            }
        }
        self.chunks = chunks
    }

    /// Distance GPS convertie en distance Mercator, unité native de strokeStart.
    public func fraction(atMeters along: Double) -> Double {
        guard meters.count >= 2, totalMeters > 0, let total = lengths.last, total > 0 else { return 0 }
        if along <= 0 { return 0 }
        if along >= totalMeters { return 1 }
        var low = 0
        var high = meters.count - 2
        while low < high {
            let mid = (low + high + 1) / 2
            if meters[mid] <= along { low = mid } else { high = mid - 1 }
        }
        let segment = meters[low + 1] - meters[low]
        let t = segment > 0 ? (along - meters[low]) / segment : 0
        return (lengths[low] + t * (lengths[low + 1] - lengths[low])) / total
    }

    /// Portions traversées seulement. Recherche logarithmique sur trajet complet.
    public func affectedChunks(from oldFraction: Double, to newFraction: Double) -> ClosedRange<Int>? {
        guard !chunks.isEmpty, oldFraction != newFraction else { return nil }
        return chunkIndex(at: min(oldFraction, newFraction))...chunkIndex(at: max(oldFraction, newFraction))
    }

    private func chunkIndex(at fraction: Double) -> Int {
        var low = 0
        var high = chunks.count - 1
        while low < high {
            let mid = (low + high) / 2
            if chunks[mid].endFraction < fraction { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private static func mercatorY(_ latitude: Double) -> Double {
        let latitude = min(max(latitude, -85.05112878), 85.05112878)
        return log(tan(.pi / 4 + latitude * .pi / 360))
    }
}

/// Même lissage à 30 ou 60 images/seconde.
public enum FrameInterpolation {
    public static func factor(reference: Double, seconds: TimeInterval) -> Double {
        1 - pow(1 - min(max(reference, 0), 1), max(seconds, 0) * 60)
    }
}
