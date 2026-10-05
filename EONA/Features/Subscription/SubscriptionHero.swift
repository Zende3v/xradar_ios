import SwiftUI

/// Radar EONA vivant. Suspend animation sous feuille, hors écran ou avec mouvements réduits.
struct EonaPlusHero: View {
    let title: String
    let subtitle: String
    let compact: Bool
    let animationsEnabled: Bool
    @State private var visibleInScroll = false
    @State private var attached = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 32

    init(title: String = "EONA+", subtitle: String, compact: Bool = false, animationsEnabled: Bool = true) {
        self.title = title
        self.subtitle = subtitle
        self.compact = compact
        self.animationsEnabled = animationsEnabled
    }

    private var paused: Bool {
        reduceMotion || scenePhase != .active || !animationsEnabled || !attached || !visibleInScroll
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.xxl) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { context in
                let time = reduceMotion ? 0.0 : context.date.timeIntervalSinceReferenceDate
                RadarIllustration(time: time, compact: compact)
            }
            .frame(height: compact ? 130 : 180)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .onScrollVisibilityChange(threshold: 0.1) { visibleInScroll = $0 }

            VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                Text(title)
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(EonaPlusStyle.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(EonaPlusStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { attached = true }
        .onDisappear { attached = false }
    }
}

private struct RadarIllustration: View {
    let time: Double
    let compact: Bool

    private var emblemSize: CGFloat { compact ? 94 : 130 }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width * 0.5, y: geometry.size.height * 0.5)
            ZStack {
                ForEach(0..<18, id: \.self) { index in
                    particle(index, center: center, size: geometry.size)
                }

                RadarEmblem(time: time)
                    .frame(width: emblemSize, height: emblemSize)
                    .rotationEffect(.degrees(sin(time * 0.33) * 7.0))
                    .rotation3DEffect(.degrees(sin(time * 0.46) * 10.0), axis: (x: 1, y: 0.6, z: 0), perspective: 0.35)
                    .offset(y: CGFloat(sin(time * 0.72) * 3.5))
                    .position(center)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func particle(_ index: Int, center: CGPoint, size: CGSize) -> some View {
        let seed = Double(index)
        let angle = seed * 2.3999632297 + time * (index.isMultiple(of: 2) ? 0.04 : -0.035)
        let radius = 0.76 + Double(index % 4) * 0.07
        let horizontalRadius = min(Double(size.width) * 0.44, compact ? 138.0 : 160.0)
        let verticalRadius = Double(size.height) * 0.43
        let x = Double(center.x) + cos(angle) * horizontalRadius * radius
        let y = Double(center.y) + sin(angle) * verticalRadius * radius
        let twinkle = (sin(time * 0.85 + seed * 1.7) + 1.0) * 0.5
        let diameter = CGFloat(index.isMultiple(of: 4) ? 4.5 : 2.5)
        let spectrum = EonaPlusStyle.spectrum

        return Circle()
            .fill(spectrum[index % spectrum.count])
            .frame(width: diameter, height: diameter)
            .opacity(0.25 + twinkle * 0.65)
            .scaleEffect(CGFloat(0.75 + twinkle * 0.35))
            .position(x: CGFloat(x), y: CGFloat(y))
    }
}

/// Emblème original : anneau, point, aiguille nord-est, arc ouvert en bas.
private struct RadarEmblem: View {
    let time: Double

    private var gradient: AngularGradient {
        let spectrum = EonaPlusStyle.spectrum
        let colours = spectrum + [spectrum[0]]
        let start = 210.0 + sin(time * 0.18) * 32.0
        return AngularGradient(colors: colours, center: .center, startAngle: .degrees(start), endAngle: .degrees(start + 360.0))
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle()
                    .trim(from: 0.125, to: 0.875)
                    .stroke(gradient, style: StrokeStyle(lineWidth: side * 0.105, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .frame(width: side * 0.86, height: side * 0.86)
                    .opacity(0.66)

                Circle()
                    .stroke(gradient, style: StrokeStyle(lineWidth: side * 0.11))
                    .frame(width: side * 0.56, height: side * 0.56)

                RadarNeedle()
                    .stroke(gradient, style: StrokeStyle(lineWidth: side * 0.105, lineCap: .round))
                    .frame(width: side, height: side)

                Circle()
                    .fill(gradient)
                    .frame(width: side * 0.205, height: side * 0.205)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

private struct RadarNeedle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.16))
        }
    }
}
