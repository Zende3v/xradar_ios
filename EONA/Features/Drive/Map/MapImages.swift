import SwiftUI
import UIKit
import EonaCore
import EonaData

/// Images the map draws itself, ported from the Android bitmaps: alert markers, the driver's
/// vehicle, other drivers, cluster badges and French road signs.
enum MapImages {
    static let markerSize: CGFloat = 30
    static let signSize: CGFloat = 37
    /// The side of the driver's vehicle image.
    static let vehicleSize: CGFloat = 40
    /// The colour the driver picked, read at draw time: the vehicle, the halo and the route follow it.
    static var accent: UIColor { rgb(EonaColor.accentValue) }

    private static let signRed = rgb(0xD22B2B)
    private static let signBlue = rgb(0x1F5AA8)
    private static let signYellow = rgb(0xF6C700)
    private static let signBlack = rgb(0x161616)

    static func rgb(_ value: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// A map marker, as on Android: a disc in the kind's [color] inside a white rim and a
    /// hairline (clear on a light or a dark map), the kind's icon on it in white, dark on a light
    /// colour (a danger's yellow).
    static func marker(glyph: UIImage?, color: UIColor, size: CGFloat = markerSize) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            let hairline: CGFloat = 0.75
            let rim: CGFloat = 1.75
            let full = CGRect(x: 0, y: 0, width: size, height: size)
            UIColor.black.withAlphaComponent(0.22).setFill()
            UIBezierPath(ovalIn: full).fill()
            UIColor.white.setFill()
            UIBezierPath(ovalIn: full.insetBy(dx: hairline, dy: hairline)).fill()
            color.setFill()
            UIBezierPath(ovalIn: full.insetBy(dx: hairline + rim, dy: hairline + rim)).fill()
            let icon = size * 0.62
            glyph?.withTintColor(luminance(color) > 0.5 ? darkGlyph : .white, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: (size - icon) / 2, y: (size - icon) / 2, width: icon, height: icon))
        }
    }

    /// Marqueur d'un signalement, identique à la carte (disque couleur du type, icône) : menu
    /// Signaler. Gardé par type, taille et thème.
    static func reportMarker(_ type: ReportType, dark: Bool, size: CGFloat) -> UIImage {
        let key = "\(type.rawValue)-\(dark)-\(size)"
        if let cached = reportMarkers[key] { return cached }
        let color = UIColor(type.alertType.color).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        let glyph: UIImage? = switch type.icon {
        case .asset(let asset): UIImage(named: asset.rawValue)
        case .symbol(let symbol): UIImage(systemName: symbol.rawValue)
        }
        let image = marker(glyph: glyph, color: color, size: size)
        reportMarkers[key] = image
        return image
    }

    private static var reportMarkers: [String: UIImage] = [:]

    /// The icon on a light marker colour.
    private static let darkGlyph = rgb(0x1C1C1E)

    /// Relative luminance of [color], 0 black to 1 white (the same measure as Compose's).
    private static func luminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0 }
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// An asset redrawn at [size].
    static func scaled(_ name: String, to size: CGSize) -> UIImage? {
        guard let image = UIImage(named: name) else { return nil }
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// A cluster badge scaled to [height], keeping its proportions.
    static func badge(_ name: String, height: CGFloat) -> UIImage? {
        guard let image = UIImage(named: name), image.size.height > 0 else { return nil }
        let width = max(1, height * image.size.width / image.size.height)
        return scaled(name, to: CGSize(width: width, height: height))
    }

    /// A cluster: the badge, and its count beside it with a halo so it reads on both basemaps.
    static func cluster(badge: UIImage?, count: String, dark: Bool) -> UIImage {
        let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let textSize = (count as NSString).size(withAttributes: [.font: font])
        let badgeSize = badge?.size ?? .zero
        let gap: CGFloat = badge == nil ? 0 : 4
        let size = CGSize(width: ceil(badgeSize.width + gap + textSize.width + 4), height: ceil(max(badgeSize.height, textSize.height)))
        return UIGraphicsImageRenderer(size: size).image { _ in
            badge?.draw(in: CGRect(x: 0, y: (size.height - badgeSize.height) / 2, width: badgeSize.width, height: badgeSize.height))
            let origin = CGPoint(x: badgeSize.width + gap, y: (size.height - textSize.height) / 2)
            let halo: [NSAttributedString.Key: Any] = [.font: font, .strokeColor: dark ? rgb(0x06070A) : UIColor.white, .strokeWidth: 7]
            (count as NSString).draw(at: origin, withAttributes: halo)
            (count as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: dark ? UIColor.white : rgb(0x0A0B0D)])
        }
    }

    // MARK: The driver's vehicle

    /// The driver on the map: [type] seen from above, nose up (the view turns it to the course),
    /// in the accent with a white outline over a soft shadow, as the arrow it replaces was. The
    /// taxi is the car with its roof light; the truck, a cab before its box; the motorcycle, its
    /// rider at the handlebar.
    static func vehicle(_ type: VehicleType) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: vehicleSize, height: vehicleSize)).image { context in
            let cg = context.cgContext
            switch type {
            case .arrow: arrow(cg)
            case .car: car(cg, taxi: false)
            case .taxi: car(cg, taxi: true)
            case .motorcycle: motorcycle(cg)
            case .truck: truck(cg)
            }
        }
    }

    private static func arrow(_ cg: CGContext) {
        let shape = UIBezierPath()
        shape.move(to: CGPoint(x: 20, y: 7))
        shape.addLine(to: CGPoint(x: 30, y: 31))
        shape.addLine(to: CGPoint(x: 20, y: 25))
        shape.addLine(to: CGPoint(x: 10, y: 31))
        shape.close()
        shape.lineJoinStyle = .round
        part(cg, shape, accent)
    }

    private static func car(_ cg: CGContext, taxi: Bool) {
        // The body and its mirrors, one shape: the body covers where they join it.
        let shape = body(CGRect(x: 12, y: 5, width: 16, height: 30), front: 5.5, rear: 4)
        shape.append(UIBezierPath(ovalIn: CGRect(x: 9.6, y: 13, width: 3.4, height: 2.2)))
        shape.append(UIBezierPath(ovalIn: CGRect(x: 27, y: 13, width: 3.4, height: 2.2)))
        part(cg, shape, accent)
        // The roof catches the light between the windscreen, wide at the bonnet, and the rear window.
        fill(UIBezierPath(roundedRect: CGRect(x: 15, y: 18.5, width: 10, height: 7.5), cornerRadius: 2.5), UIColor.white.withAlphaComponent(0.14))
        window(trapezoid(top: 12.5, bottom: 17.5, topHalf: 6, bottomHalf: 5))
        window(trapezoid(top: 27, bottom: 30.5, topHalf: 5, bottomHalf: 5.6))
        // Headlights ahead, tail lights behind: which way it goes, at a glance.
        for x: CGFloat in [14.6, 22.6] {
            fill(UIBezierPath(roundedRect: CGRect(x: x, y: 6.4, width: 2.8, height: 1.6), cornerRadius: 0.8), .white)
            fill(UIBezierPath(roundedRect: CGRect(x: x, y: 32.8, width: 2.8, height: 1.2), cornerRadius: 0.6), tailRed)
        }
        if taxi {
            // The roof light, in the yellow and black of the road signs.
            let light = UIBezierPath(roundedRect: CGRect(x: 15.5, y: 20.4, width: 9, height: 3.8), cornerRadius: 1.2)
            fill(light, signYellow)
            stroke(light, signBlack, 0.9)
        }
    }

    private static func motorcycle(_ cg: CGContext) {
        // Tyres, front and rear, then the bike and its handlebar across.
        part(cg, UIBezierPath(roundedRect: CGRect(x: 18.4, y: 4.5, width: 3.2, height: 8), cornerRadius: 1.6), signBlack, outline: 1.8)
        part(cg, UIBezierPath(roundedRect: CGRect(x: 18.1, y: 27.5, width: 3.8, height: 8.5), cornerRadius: 1.9), signBlack, outline: 1.8)
        part(cg, UIBezierPath(roundedRect: CGRect(x: 16.6, y: 10, width: 6.8, height: 21), cornerRadius: 3.4), accent)
        part(cg, UIBezierPath(roundedRect: CGRect(x: 12, y: 12.4, width: 16, height: 2), cornerRadius: 1), signBlack, outline: 1.6)
        // The rider: arms to the grips, shoulders, helmet.
        let arms = UIBezierPath()
        arms.move(to: CGPoint(x: 15.4, y: 19))
        arms.addLine(to: CGPoint(x: 13.6, y: 13.6))
        arms.move(to: CGPoint(x: 24.6, y: 19))
        arms.addLine(to: CGPoint(x: 26.4, y: 13.6))
        stroke(arms, .white, 3.6)
        stroke(arms, accent, 1.8)
        part(cg, UIBezierPath(ovalIn: CGRect(x: 13.5, y: 17, width: 13, height: 7.5)), accent)
        part(cg, UIBezierPath(ovalIn: CGRect(x: 16.7, y: 16.4, width: 6.6, height: 6.6)), signBlack, outline: 1.6)
    }

    private static func truck(_ cg: CGContext) {
        // The box behind, a shade apart from the cab, ribbed like a trailer.
        let box = CGRect(x: 11.5, y: 13.5, width: 17, height: 23)
        part(cg, UIBezierPath(roundedRect: box, cornerRadius: 2), boxColor)
        let ribs = UIBezierPath()
        for y: CGFloat in [19.3, 25, 30.7] {
            ribs.move(to: CGPoint(x: box.minX + 2.5, y: y))
            ribs.addLine(to: CGPoint(x: box.maxX - 2.5, y: y))
        }
        stroke(ribs, UIColor.white.withAlphaComponent(0.4), 0.9)
        // The cab ahead, with its mirrors and its windscreen.
        let cab = body(CGRect(x: 12.5, y: 3.5, width: 15, height: 9), front: 3.5, rear: 1.5)
        cab.append(UIBezierPath(ovalIn: CGRect(x: 10.2, y: 8, width: 3, height: 2)))
        cab.append(UIBezierPath(ovalIn: CGRect(x: 26.8, y: 8, width: 3, height: 2)))
        part(cg, cab, accent)
        window(trapezoid(top: 5.4, bottom: 8.4, topHalf: 5.4, bottomHalf: 5))
    }

    /// A piece of the vehicle: its white outline over a soft shadow, then its colour.
    private static func part(_ cg: CGContext, _ path: UIBezierPath, _ color: UIColor, outline: CGFloat = 2.2) {
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: 2, color: UIColor.black.withAlphaComponent(0.35).cgColor)
        stroke(path, .white, outline)
        cg.restoreGState()
        fill(path, color)
    }

    /// A window: a deep shade of the accent, readable on every colour the driver can pick.
    private static func window(_ path: UIBezierPath) {
        let glass = rgb(EonaColor.shade(EonaColor.accentValue, 0.3))
        fill(path, glass)
        stroke(path, glass, 0.8)
    }

    /// The truck's box: paler than a dark accent, deeper than a light one, apart from the cab.
    private static var boxColor: UIColor {
        let value = EonaColor.accentValue
        if EonaColor.isLight(value) { return rgb(EonaColor.shade(value, 0.8)) }
        let paler = { (shift: UInt32) -> CGFloat in
            let channel = CGFloat((value >> shift) & 0xFF) / 255
            return channel + (1 - channel) * 0.25
        }
        return UIColor(red: paler(16), green: paler(8), blue: paler(0), alpha: 1)
    }

    private static let tailRed = rgb(0xE23B3B)

    /// A body seen from above: a rectangle whose front (top) and rear corners round off apart.
    private static func body(_ rect: CGRect, front: CGFloat, rear: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + front, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - front, y: rect.minY))
        path.addArc(withCenter: CGPoint(x: rect.maxX - front, y: rect.minY + front), radius: front, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rear))
        path.addArc(withCenter: CGPoint(x: rect.maxX - rear, y: rect.maxY - rear), radius: rear, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX + rear, y: rect.maxY))
        path.addArc(withCenter: CGPoint(x: rect.minX + rear, y: rect.maxY - rear), radius: rear, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + front))
        path.addArc(withCenter: CGPoint(x: rect.minX + front, y: rect.minY + front), radius: front, startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
        path.close()
        return path
    }

    /// A trapezoid on the vehicle's axis: [topHalf] to each side at [top], [bottomHalf] at [bottom].
    private static func trapezoid(top: CGFloat, bottom: CGFloat, topHalf: CGFloat, bottomHalf: CGFloat) -> UIBezierPath {
        let axis = vehicleSize / 2
        let path = UIBezierPath()
        path.move(to: CGPoint(x: axis - topHalf, y: top))
        path.addLine(to: CGPoint(x: axis + topHalf, y: top))
        path.addLine(to: CGPoint(x: axis + bottomHalf, y: bottom))
        path.addLine(to: CGPoint(x: axis - bottomHalf, y: bottom))
        path.close()
        return path
    }

    // MARK: Road signs

    /// A recognizable French road sign.
    static func sign(_ type: SignType, size s: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { _ in
            let cx = s / 2
            let cy = s / 2
            let r = s * 0.44
            switch type {
            case .stop:
                let octagon = polygon(cx, cy, r, sides: 8, startDeg: -22.5)
                fill(octagon, signRed)
                stroke(octagon, .white, s * 0.05)
                drawCentered("STOP", font: .boldSystemFont(ofSize: s * 0.26), color: .white, at: CGPoint(x: cx, y: cy))

            case .giveWay:
                let triangle = triangleDown(cx, cy, r * 1.05)
                fill(triangle, .white)
                stroke(triangle, signRed, s * 0.11)

            case .levelCrossing:
                let disc = UIBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
                fill(disc, .white)
                stroke(disc, signRed, s * 0.06)
                let arm = r * 0.78
                let cross = UIBezierPath()
                cross.move(to: CGPoint(x: cx - arm, y: cy - arm))
                cross.addLine(to: CGPoint(x: cx + arm, y: cy + arm))
                cross.move(to: CGPoint(x: cx + arm, y: cy - arm))
                cross.addLine(to: CGPoint(x: cx - arm, y: cy + arm))
                stroke(cross, signRed, s * 0.16)
                stroke(cross, .white, s * 0.08)

            case .noEntry:
                let disc = UIBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
                fill(disc, signRed)
                stroke(disc, .white, s * 0.03)
                let bar = UIBezierPath(roundedRect: CGRect(x: cx - r * 0.55, y: cy - r * 0.17, width: r * 1.1, height: r * 0.34), cornerRadius: s * 0.03)
                fill(bar, .white)

            case .roundabout:
                fill(UIBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)), signBlue)
                let ring = r * 0.42
                for k in 0..<3 {
                    let a = (90.0 + Double(k) * 120.0) * .pi / 180
                    let a2 = a + 70.0 * .pi / 180
                    let start = CGPoint(x: cx + ring * cos(a), y: cy + ring * sin(a))
                    let end = CGPoint(x: cx + ring * cos(a2), y: cy + ring * sin(a2))
                    let segment = UIBezierPath()
                    segment.move(to: start)
                    segment.addLine(to: end)
                    stroke(segment, .white, s * 0.08)
                    fill(arrowHead(end, directionDeg: a2 * 180 / .pi + 90, size: s * 0.11), .white)
                }

            case .crossing:
                fill(UIBezierPath(roundedRect: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), cornerRadius: s * 0.08), signBlue)
                let head = r * 0.16
                fill(UIBezierPath(ovalIn: CGRect(x: cx - head, y: cy - r * 0.42 - head, width: 2 * head, height: 2 * head)), .white)
                let body = UIBezierPath()
                body.move(to: CGPoint(x: cx, y: cy - r * 0.24)); body.addLine(to: CGPoint(x: cx, y: cy + r * 0.18))
                body.move(to: CGPoint(x: cx, y: cy - r * 0.10)); body.addLine(to: CGPoint(x: cx + r * 0.28, y: cy + r * 0.02))
                body.move(to: CGPoint(x: cx, y: cy - r * 0.10)); body.addLine(to: CGPoint(x: cx - r * 0.22, y: cy + r * 0.04))
                body.move(to: CGPoint(x: cx, y: cy + r * 0.18)); body.addLine(to: CGPoint(x: cx + r * 0.24, y: cy + r * 0.5))
                body.move(to: CGPoint(x: cx, y: cy + r * 0.18)); body.addLine(to: CGPoint(x: cx - r * 0.20, y: cy + r * 0.5))
                stroke(body, .white, s * 0.055)

            case .construction:
                let triangle = triangleUp(cx, cy, r * 1.05)
                fill(triangle, signYellow)
                stroke(triangle, signRed, s * 0.09)
                let head = r * 0.11
                fill(UIBezierPath(ovalIn: CGRect(x: cx - r * 0.1 - head, y: cy - r * 0.05 - head, width: 2 * head, height: 2 * head)), signBlack)
                let worker = UIBezierPath()
                worker.move(to: CGPoint(x: cx - r * 0.1, y: cy + r * 0.05)); worker.addLine(to: CGPoint(x: cx - r * 0.1, y: cy + r * 0.32))
                worker.move(to: CGPoint(x: cx - r * 0.1, y: cy + r * 0.12)); worker.addLine(to: CGPoint(x: cx + r * 0.28, y: cy - r * 0.12))
                stroke(worker, signBlack, s * 0.05)
                let mound = UIBezierPath()
                mound.move(to: CGPoint(x: cx - r * 0.35, y: cy + r * 0.42))
                mound.addLine(to: CGPoint(x: cx + r * 0.02, y: cy + r * 0.42))
                mound.addLine(to: CGPoint(x: cx - r * 0.16, y: cy + r * 0.28))
                mound.close()
                fill(mound, signBlack)

            case .trafficSignals:
                fill(UIBezierPath(roundedRect: CGRect(x: cx - r * 0.5, y: cy - r, width: r, height: 2 * r), cornerRadius: s * 0.06), signBlack)
                let lamp = r * 0.22
                for (offset, color) in [(-0.5, rgb(0xE23B3B)), (0.0, rgb(0xF3A825)), (0.5, rgb(0x2FBF57))] {
                    fill(UIBezierPath(ovalIn: CGRect(x: cx - lamp, y: cy + r * offset - lamp, width: 2 * lamp, height: 2 * lamp)), color)
                }

            case .speedLimit:
                fill(UIBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)), .white)
                let inner = r - s * 0.07
                stroke(UIBezierPath(ovalIn: CGRect(x: cx - inner, y: cy - inner, width: 2 * inner, height: 2 * inner)), signRed, s * 0.12)
            }
        }
    }

    /// Round French speed-limit sign: white disc, red ring, black number.
    static func speedSign(_ value: Int, size s: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { _ in
            let c = s / 2
            let r = s * 0.46
            fill(UIBezierPath(ovalIn: CGRect(x: c - r, y: c - r, width: 2 * r, height: 2 * r)), .white)
            let inner = r - s * 0.07
            stroke(UIBezierPath(ovalIn: CGRect(x: c - inner, y: c - inner, width: 2 * inner, height: 2 * inner)), signRed, s * 0.13)
            let font = UIFont.boldSystemFont(ofSize: s * (value >= 100 ? 0.40 : 0.46))
            drawCentered(String(value), font: font, color: signBlack, at: CGPoint(x: c, y: c))
        }
    }

    // MARK: Drawing helpers

    private static func fill(_ path: UIBezierPath, _ color: UIColor) {
        color.setFill()
        path.fill()
    }

    private static func stroke(_ path: UIBezierPath, _ color: UIColor, _ width: CGFloat) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    private static func drawCentered(_ text: String, font: UIFont, color: UIColor, at center: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
    }

    private static func polygon(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, sides: Int, startDeg: Double) -> UIBezierPath {
        let path = UIBezierPath()
        for i in 0..<sides {
            let a = (startDeg + 360.0 * Double(i) / Double(sides)) * .pi / 180
            let point = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.close()
        return path
    }

    private static func triangleDown(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: cx - r, y: cy - r * 0.7))
        path.addLine(to: CGPoint(x: cx + r, y: cy - r * 0.7))
        path.addLine(to: CGPoint(x: cx, y: cy + r * 0.85))
        path.close()
        return path
    }

    private static func triangleUp(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: cx, y: cy - r * 0.85))
        path.addLine(to: CGPoint(x: cx + r, y: cy + r * 0.7))
        path.addLine(to: CGPoint(x: cx - r, y: cy + r * 0.7))
        path.close()
        return path
    }

    private static func arrowHead(_ tip: CGPoint, directionDeg: Double, size: CGFloat) -> UIBezierPath {
        let a = directionDeg * .pi / 180
        let left = a + 140 * .pi / 180
        let right = a - 140 * .pi / 180
        let path = UIBezierPath()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x + size * cos(left), y: tip.y + size * sin(left)))
        path.addLine(to: CGPoint(x: tip.x + size * cos(right), y: tip.y + size * sin(right)))
        path.close()
        return path
    }
}
