import MapKit
import EonaCore

/// Deux traits vectoriels courts. MapKit conserve projection, ordre et netteté au zoom.
final class RouteVectorChunk {
    let portion: RouteStrokePlan.Chunk
    let glow: MKPolyline
    let core: MKPolyline
    var glowRenderer: MKPolylineRenderer?
    var coreRenderer: MKGradientPolylineRenderer?
    var fraction: CGFloat = 0

    init(points: [GeoPoint], portion: RouteStrokePlan.Chunk) {
        self.portion = portion
        let coordinates = points[portion.firstPoint...portion.lastPoint].map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        glow = MKPolyline(coordinates: coordinates, count: coordinates.count)
        core = MKPolyline(coordinates: coordinates, count: coordinates.count)
    }

    func trim(to wholeFraction: Double) {
        let next = CGFloat(portion.localFraction(wholeFraction))
        guard next != fraction else { return }
        fraction = next
        if let glowRenderer { configureProgress(glowRenderer) }
        if let coreRenderer { configureProgress(coreRenderer) }
    }

    func configureProgress(_ renderer: MKPolylineRenderer) {
        renderer.strokeStart = fraction
        renderer.alpha = fraction >= 1 ? 0 : 1
        // Propriétés natives : aucune invalidation bitmap du trajet entier.
    }
}

/// Gradient global recadré par portion. Couleurs identiques aux raccords.
struct RouteVectorGradient {
    var colors: [UIColor]
    var locations: [CGFloat]

    func apply(to renderer: MKGradientPolylineRenderer, portion: RouteStrokePlan.Chunk) {
        let start = CGFloat(portion.startFraction)
        let end = CGFloat(portion.endFraction)
        guard end > start else { return }
        var localColors = [color(at: start)]
        var localLocations: [CGFloat] = [0]
        for index in locations.indices where locations[index] > start && locations[index] < end {
            localColors.append(colors[index])
            localLocations.append((locations[index] - start) / (end - start))
        }
        localColors.append(color(at: end))
        localLocations.append(1)
        renderer.setColors(localColors, locations: localLocations)
    }

    private func color(at fraction: CGFloat) -> UIColor {
        var index = 0
        while index + 1 < locations.count, locations[index + 1] <= fraction { index += 1 }
        guard index + 1 < colors.count else { return colors[index] }
        let length = locations[index + 1] - locations[index]
        let t = length > 0 ? min(max((fraction - locations[index]) / length, 0), 1) : 0
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        colors[index].getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        colors[index + 1].getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t,
                       blue: ab + (bb - ab) * t, alpha: aa + (ba - aa) * t)
    }
}
