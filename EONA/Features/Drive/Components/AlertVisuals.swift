import SwiftUI
import EonaCore

/// The only place road-event types map to a color and an icon, as on Android.
extension AlertType {
    var color: Color {
        switch self {
        case .radarFixed, .camera: EonaColor.radarFixed
        case .radarMobile, .radarCar: EonaColor.radarMobile
        case .controlZone, .roadwork: EonaColor.controlZone
        case .hazard, .accident: EonaColor.hazard
        }
    }

    /// Arthur's report icons (30/09); a plain danger has none in the set: the warning sign.
    var icon: EonaIconImage {
        switch self {
        case .radarFixed: .asset(.reportRadarFixed)
        case .radarMobile: .asset(.reportRadarMobile)
        case .controlZone: .asset(.reportControlZone)
        case .camera: .asset(.reportCamera)
        case .hazard: .symbol(.warning)
        case .accident: .asset(.reportAccident)
        case .roadwork: .asset(.reportRoadworks)
        case .radarCar: .asset(.reportRadarCar)
        }
    }
}

extension ReportType {
    /// Its own icon (Arthur's set, 30/09), finer than its alert's: the map's marker, the report
    /// picker, its switch in "Options". The legacy danger keeps the warning sign.
    var icon: EonaIconImage {
        switch self {
        case .voitureRadar: .asset(.reportRadarCar)
        case .camera: .asset(.reportCamera)
        case .hazard: .symbol(.warning)
        case .radarMobile: .asset(.reportRadarMobile)
        case .controlZone: .asset(.reportControlZone)
        case .stoppedVehicle: .asset(.reportStoppedVehicle)
        case .accident: .asset(.reportAccident)
        case .objectOnRoad: .asset(.reportObjectOnRoad)
        case .trafficJam: .asset(.reportTrafficJam)
        case .damagedRoad: .asset(.reportDamagedRoad)
        case .roadworks: .asset(.reportRoadworks)
        case .slipperyRoad: .asset(.reportSlipperyRoad)
        case .lowVisibility: .asset(.reportLowVisibility)
        case .roadCrew: .asset(.reportRoadCrew)
        case .wrongWay: .asset(.reportWrongWay)
        }
    }
}

extension Maneuver {
    /// The arrow of the guidance banner.
    var icon: EonaIconImage {
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
                Circle().strokeBorder(EonaColor.limitRing, lineWidth: size * 0.12)
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
            .foregroundStyle(EonaColor.textTertiary)
            .frame(width: size, height: size)
            .background(EonaColor.surfaceHigh, in: .circle)
            .overlay {
                Circle().strokeBorder(EonaColor.border, lineWidth: size * 0.10)
            }
            .accessibilityLabel("Limitation inconnue")
    }
}
