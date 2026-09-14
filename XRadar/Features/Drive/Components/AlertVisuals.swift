import SwiftUI
import XRadarCore

/// The only place road-event types map to a color and an icon, as on Android.
extension AlertType {
    var color: Color {
        switch self {
        case .radarFixed, .camera: XRadarColor.radarFixed
        case .radarMobile, .radarCar: XRadarColor.radarMobile
        case .controlZone, .roadwork: XRadarColor.controlZone
        case .hazard, .accident: XRadarColor.hazard
        }
    }

    var icon: XRadarIconImage {
        switch self {
        case .radarFixed, .radarMobile: .asset(.radar)
        case .controlZone: .asset(.shield)
        case .camera: .asset(.camera)
        case .hazard: .symbol(.warning)
        case .accident: .asset(.accident)
        case .roadwork: .asset(.construction)
        case .radarCar: .asset(.radarCar)
        }
    }
}

extension Maneuver {
    /// The arrow of the guidance banner.
    var icon: XRadarIconImage {
        switch self {
        case .depart: .symbol(.navigation)
        case .straight: .asset(.maneuverStraight)
        case .slightLeft, .forkLeft: .asset(.maneuverSlightLeft)
        case .slightRight, .ramp, .forkRight: .asset(.maneuverSlightRight)
        case .left: .asset(.maneuverLeft)
        case .right: .asset(.maneuverRight)
        case .sharpLeft: .asset(.maneuverSharpLeft)
        case .sharpRight: .asset(.maneuverSharpRight)
        case .uturn: .asset(.maneuverUturn)
        case .roundabout: .asset(.maneuverRoundabout)
        case .merge: .asset(.maneuverMerge)
        case .arrive: .symbol(.flag)
        }
    }
}

/// European speed-limit sign: red ring, black number on white.
struct SpeedLimitSign: View {
    let limitKmh: Int
    var size: CGFloat = 64

    var body: some View {
        Text(String(limitKmh))
            .font(.system(size: size * 0.36, weight: .bold).monospacedDigit())
            .foregroundStyle(Color(red: 10.0 / 255, green: 11.0 / 255, blue: 13.0 / 255))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: size, height: size)
            .background(Color.white, in: .circle)
            .overlay {
                Circle().strokeBorder(XRadarColor.danger, lineWidth: size * 0.12)
            }
            .accessibilityLabel("Limitation \(limitKmh) km/h")
    }
}

/// The limit slot keeps its place when no limit is known: an empty sign reads better than a jump.
struct UnknownLimitSign: View {
    var size: CGFloat = 64

    var body: some View {
        Text("--")
            .font(.xrBodyStrong)
            .foregroundStyle(XRadarColor.textTertiary)
            .frame(width: size, height: size)
            .background(XRadarColor.surfaceHigh, in: .circle)
            .overlay {
                Circle().strokeBorder(XRadarColor.border, lineWidth: size * 0.10)
            }
            .accessibilityLabel("Limitation inconnue")
    }
}
