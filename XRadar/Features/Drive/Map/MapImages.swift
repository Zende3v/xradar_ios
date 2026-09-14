import UIKit
import XRadarCore

/// Images the map draws itself, ported from the Android bitmaps: alert markers, the driver's
/// arrow, other drivers, cluster badges and French road signs.
enum MapImages {
    static let markerSize: CGFloat = 30
    static let signSize: CGFloat = 37
    static let accent = rgb(0x2CD5E0)

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

    /// Round marker: white chip, colored ring, the glyph in that color.
    static func marker(glyph: UIImage?, color: UIColor, size: CGFloat = markerSize) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            let ring: CGFloat = 2
            let rect = CGRect(x: ring / 2, y: ring / 2, width: size - ring, height: size - ring)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect).fill()
            let circle = UIBezierPath(ovalIn: rect)
            circle.lineWidth = ring
            color.setStroke()
            circle.stroke()
            let icon = size * 0.56
            glyph?.withTintColor(color, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: (size - icon) / 2, y: (size - icon) / 2, width: icon, height: icon))
        }
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

    /// The driver: a crisp chevron pointing north, in the accent with a white outline.
    static func arrow() -> UIImage {
        let size: CGFloat = 28
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: size * 0.5, y: size * 0.12))
            path.addLine(to: CGPoint(x: size * 0.82, y: size * 0.86))
            path.addLine(to: CGPoint(x: size * 0.5, y: size * 0.68))
            path.addLine(to: CGPoint(x: size * 0.18, y: size * 0.86))
            path.close()
            path.lineJoinStyle = .round
            path.lineWidth = size * 0.09
            UIColor.white.setStroke()
            path.stroke()
            accent.setFill()
            path.fill()
        }
    }

    /// The straight "navigation" arrow of the Android line icons, for other drivers.
    static func navigationGlyph() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 12, y: 4))
            path.addLine(to: CGPoint(x: 12, y: 20))
            path.move(to: CGPoint(x: 6, y: 10))
            path.addLine(to: CGPoint(x: 12, y: 4))
            path.addLine(to: CGPoint(x: 18, y: 10))
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor.black.setStroke()
            path.stroke()
        }
        .withRenderingMode(.alwaysTemplate)
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
