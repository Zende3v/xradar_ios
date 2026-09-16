import SwiftUI
import XRadarCore

/// Generic icons: SF Symbols, like the rest of iOS.
enum XRadarSymbol: String, CaseIterable {
    case back = "chevron.backward"
    case chevronLeft = "chevron.left"
    case chevronRight = "chevron.right"
    case chevronUp = "chevron.up"
    case chevronDown = "chevron.down"
    case close = "xmark"
    case check = "checkmark"
    case plus
    case minus
    case menu = "line.3.horizontal"
    case more = "ellipsis"
    case search = "magnifyingglass"
    case settings = "gearshape"
    case info = "info.circle"
    case bell
    case bellOff = "bell.slash"
    case bellRinging = "bell.badge"
    case user = "person.crop.circle"
    case history = "clock.arrow.circlepath"
    case star
    case starFill = "star.fill"
    case home = "house"
    case volumeOn = "speaker.wave.2.fill"
    case volumeOff = "speaker.slash.fill"
    case navigation = "location.north.fill"
    case mapPin = "mappin.and.ellipse"
    case flag
    case gps = "location"
    case recenter = "location.fill"
    case layers = "square.3.layers.3d"
    case warning = "exclamationmark.triangle"
    case stats = "chart.bar"
    case referral = "gift"
    case diagnostic = "stethoscope"
    case music = "music.note"
    case musicPrevious = "backward.fill"
    case musicNext = "forward.fill"
    case play = "play.fill"
    case pause = "pause.fill"
    case fog = "cloud.fog"
    case crown = "crown.fill"
    case appleLogo = "apple.logo"
}

/// XRadar's own icons, drawn for the Android app (asset catalog). Line icons and report icons
/// take the foreground color; place icons keep their colors.
enum XRadarAsset: String, CaseIterable {
    // Guidance arrows
    case maneuverStraight = "ic_line_maneuver_straight"
    case maneuverLeft = "ic_line_maneuver_left"
    case maneuverRight = "ic_line_maneuver_right"
    case maneuverSlightLeft = "ic_line_maneuver_slight_left"
    case maneuverSlightRight = "ic_line_maneuver_slight_right"
    case maneuverSharpLeft = "ic_line_maneuver_sharp_left"
    case maneuverSharpRight = "ic_line_maneuver_sharp_right"
    case maneuverUturn = "ic_line_maneuver_uturn"
    case maneuverMerge = "ic_line_maneuver_merge"
    case maneuverRoundabout = "ic_line_maneuver_roundabout"

    // Road safety and signs
    case radar = "ic_line_radar"
    case camera = "ic_line_camera"
    case radarCar = "ic_line_radar_car"
    case toll = "ic_line_toll"
    case shield = "ic_line_shield"
    case construction = "ic_line_construction"
    case accident = "ic_line_accident"
    case trafficLight = "ic_line_traffic_light"
    case stopSign = "ic_line_stop_sign"
    case yieldSign = "ic_line_yield"
    case crossing = "ic_line_crossing"
    case noEntry = "ic_line_no_entry"

    // Reports
    case report = "ic_report"
    case reportRadarCar = "ic_report_radar_car"
    case reportRadarMobile = "ic_report_radar_mobile"
    case reportAccident = "ic_report_accident"
    case reportStoppedVehicle = "ic_report_stopped_vehicle"
    case reportObjectOnRoad = "ic_report_object_on_road"
    case reportTrafficJam = "ic_report_traffic_jam"
    case reportDamagedRoad = "ic_report_damaged_road"
    case reportRoadCrew = "ic_report_road_crew"
    case reportSlipperyRoad = "ic_report_slippery_road"
    case reportWrongWay = "ic_report_wrong_way"

    // Place categories
    case placeFuel = "ic_place_fuel"
    case placeCharging = "ic_place_charging"
    case placeParking = "ic_place_parking"
    case placeTobacco = "ic_place_tobacco"
    case placeGarage = "ic_place_garage"
    case placeHotel = "ic_place_hotel"
    case placeAtm = "ic_place_atm"
}

extension Image {
    init(_ symbol: XRadarSymbol) {
        self.init(systemName: symbol.rawValue)
    }

    init(_ asset: XRadarAsset) {
        self.init(asset.rawValue)
    }
}

/// Either kind of icon, for components that accept both.
enum XRadarIconImage: Hashable {
    case symbol(XRadarSymbol)
    case asset(XRadarAsset)
}

/// An icon at a size: symbols scale with their font, assets are fitted into the square.
struct XRadarIconView: View {
    let icon: XRadarIconImage
    var size: CGFloat = 24

    var body: some View {
        switch icon {
        case .symbol(let symbol):
            Image(symbol)
                .font(.system(size: size * 0.85, weight: .semibold))
                .frame(width: size, height: size)
        case .asset(let asset):
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }
}

extension PlaceCategory {
    /// The icon inside the category square.
    var icon: XRadarAsset {
        switch self {
        case .fuel: .placeFuel
        case .charging: .placeCharging
        case .parking: .placeParking
        case .tobacco: .placeTobacco
        case .garage: .placeGarage
        case .hotel: .placeHotel
        case .atm: .placeAtm
        }
    }

    /// One flat theme color per category, behind its icon.
    var color: Color {
        switch self {
        case .fuel: XRadarColor.radarMobile
        case .charging: XRadarColor.success
        case .parking: XRadarColor.info
        case .tobacco: XRadarColor.danger
        case .garage: XRadarColor.textSecondary
        case .hotel: XRadarColor.controlZone
        case .atm: XRadarColor.radarFixed
        }
    }
}
