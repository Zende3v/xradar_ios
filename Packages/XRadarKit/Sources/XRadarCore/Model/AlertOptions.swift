public extension ReportType {
    /// The report categories the driver turns off one by one in the HUD's "Options", in that
    /// order. A traffic jam is not an alert (the route can avoid it instead), and the legacy
    /// "Danger" has no switch.
    static let alertOptions: [ReportType] = [
        .radarMobile,
        .camera,
        .controlZone,
        .voitureRadar,
        .stoppedVehicle,
        .accident,
        .objectOnRoad,
        .damagedRoad,
        .roadworks,
        .slipperyRoad,
        .lowVisibility,
        .roadCrew,
        .wrongWay,
    ]

    /// Alerts for this category reach the driver (shown ahead, spoken, sounded).
    var raisesAlerts: Bool {
        self != .trafficJam
    }
}

public extension AlertType {
    /// Speed enforcement: its approach sounds like a radar detector, the rest like a road hazard.
    var isEnforcement: Bool {
        switch self {
        case .radarFixed, .radarMobile, .camera, .controlZone, .radarCar: true
        case .hazard, .accident, .roadwork: false
        }
    }
}
