import Foundation
import Observation
import EonaCore

/// User-tunable alert preferences, edited from the trip menu and read to filter alerts.
public struct AlertPreferences: Sendable, Hashable {
    /// Official fixed speed radars.
    public var radarFixed = true
    /// Report categories turned off one by one (ReportType.alertOptions). Red-light radars follow
    /// the camera's switch.
    public var hiddenReports: Set<ReportType> = []
    public var sound = true
    public var vibration = true
    /// Spoken alert and maneuver announcements.
    public var voice = true
    /// What warns the driver over the speed limit.
    public var overspeed: OverspeedWarning = .voice
    /// "Volume Guidage" (0...1): the spoken turn-by-turn and the trip's own announcements.
    public var guidanceVolume = 1.0
    /// "Volume alertes" (0...1): the alert sounds and the spoken alerts (radars, dangers,
    /// overspeed).
    public var alertVolume = 1.0

    public init() {}

    /// Whether reports of [type] reach the driver.
    public func shows(_ type: ReportType) -> Bool {
        !hiddenReports.contains(type)
    }

    public mutating func toggle(_ type: ReportType) {
        if hiddenReports.contains(type) {
            hiddenReports.remove(type)
        } else {
            hiddenReports.insert(type)
        }
    }
}

/// "Dépassement limitation": the spoken warning, a beep of its own, or nothing.
public enum OverspeedWarning: String, Sendable, Hashable, CaseIterable {
    case voice
    case beep
    case off
}

/// "Thème général", for the whole app, the map and the HUD over it: "Auto" follows day and night
/// where the driver is, "Jour" and "Nuit" pin it.
public enum AppTheme: String, Sendable, Hashable, CaseIterable {
    case auto
    case day
    case night
}

/// The colour the driver picked for everything interactive: buttons, the route, the dock.
/// Stored as its hex, so a colour added later needs no migration.
public enum AccentColor: String, Sendable, Hashable, CaseIterable {
    case cyan = "2CD5E0"
    case coral = "FF5E36"
    case lemon = "FFF342"
    case lime = "CFFF2B"
    case mint = "A8FFD8"
    case turquoise = "52FFEC"
    case azure = "009EFF"
    case lavender = "856EFF"
    case indigo = "4E21FF"
    case violet = "8500FF"
    case magenta = "E100FF"

    public var label: String {
        switch self {
        case .cyan: "Cyan"
        case .coral: "Corail"
        case .lemon: "Citron"
        case .lime: "Citron vert"
        case .mint: "Menthe"
        case .turquoise: "Turquoise"
        case .azure: "Azur"
        case .lavender: "Lavande"
        case .indigo: "Indigo"
        case .violet: "Violet"
        case .magenta: "Magenta"
        }
    }

    /// The colour itself, as 0xRRGGBB.
    public var value: UInt32 { UInt32(rawValue, radix: 16) ?? 0x2CD5E0 }
}

/// Look-and-feel and routing choices, edited from Réglages and the trip menu.
public struct AppSettings: Sendable, Hashable {
    public var theme: AppTheme = .auto
    public var accent: AccentColor = .cyan
    /// Ask the router to keep the trip off toll roads.
    public var avoidTolls = false
    /// Ask the router to keep the trip off motorways.
    public var avoidHighways = false
    /// Ask the router to go around the traffic jams drivers reported.
    public var avoidTraffic = false
    /// Fuel whose price the nearby "Carburant" search shows, picked there.
    public var preferredFuel: FuelType = .gazole
    /// "Proche uniquement" in the nearby "Carburant" search: the nearest open stations, no price.
    public var fuelNearestOnly = false
    // Confidentialité.
    /// "Aide au trafic partagé": a slowdown on a fast road is sent anonymously to the shared
    /// traffic (and may ask "Ralentissement du trafic ?"). Off: nothing of this driver feeds it.
    public var sharedTraffic = true
    /// "Suggestions de trajets": the destinations picked are kept on the phone and offered again
    /// in the search ("Récents").
    public var tripSuggestions = true
    /// "Statistiques de conduite": trips and driving time are recorded and sent to the account.
    public var drivingStats = true
    /// "Présence et position": the backend counts the app open and a trip running, and the
    /// EONA team sees where this driver is. Off unless the driver turns it on.
    public var presence = false
    /// "Temps d'utilisation": the time spent with the app open adds up on the account.
    public var usageTime = true
    /// True once the driver has answered the question about sharing their position: the app asks
    /// once, then never again.
    public var presenceAsked = false

    public init() {}
}

/// App preferences, one UserDefaults key per value like the Android SharedPreferences.
@MainActor
@Observable
public final class PreferencesStore {
    public private(set) var alerts: AlertPreferences
    public private(set) var settings: AppSettings

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        alerts = Self.readAlerts(defaults)
        settings = Self.readSettings(defaults)
    }

    public func updateAlerts(_ change: (inout AlertPreferences) -> Void) {
        var updated = alerts
        change(&updated)
        alerts = updated
        defaults.set(updated.radarFixed, forKey: Self.key("radarFixed"))
        defaults.set(updated.hiddenReports.map(\.rawValue).sorted(), forKey: Self.key("hiddenReports"))
        defaults.set(updated.sound, forKey: Self.key("sound"))
        defaults.set(updated.vibration, forKey: Self.key("vibration"))
        defaults.set(updated.voice, forKey: Self.key("voice"))
        defaults.set(updated.overspeed.rawValue, forKey: Self.key("overspeed"))
        defaults.set(updated.guidanceVolume, forKey: Self.key("guidanceVolume"))
        defaults.set(updated.alertVolume, forKey: Self.key("alertVolume"))
    }

    public func updateSettings(_ change: (inout AppSettings) -> Void) {
        var updated = settings
        change(&updated)
        settings = updated
        defaults.set(updated.theme.rawValue, forKey: Self.key("theme"))
        defaults.set(updated.accent.rawValue, forKey: Self.key("accent"))
        // The app theme and the basemap of earlier builds, merged into [theme].
        defaults.removeObject(forKey: Self.key("themeMode"))
        defaults.removeObject(forKey: Self.key("mapStyle"))
        defaults.set(updated.avoidTolls, forKey: Self.key("avoidTolls"))
        defaults.set(updated.avoidHighways, forKey: Self.key("avoidHighways"))
        defaults.set(updated.avoidTraffic, forKey: Self.key("avoidTraffic"))
        defaults.set(updated.preferredFuel.rawValue, forKey: Self.key("preferredFuel"))
        defaults.set(updated.fuelNearestOnly, forKey: Self.key("fuelNearestOnly"))
        // Stored under its first name: the choice made before the rename stays.
        defaults.set(updated.sharedTraffic, forKey: Self.key("shareSlowdowns"))
        defaults.set(updated.tripSuggestions, forKey: Self.key("tripSuggestions"))
        defaults.set(updated.drivingStats, forKey: Self.key("drivingStats"))
        defaults.set(updated.presence, forKey: Self.key("presence"))
        defaults.set(updated.usageTime, forKey: Self.key("usageTime"))
        defaults.set(updated.presenceAsked, forKey: Self.key("presenceAsked"))
    }

    private static func key(_ name: String) -> String {
        "xr_prefs.\(name)"
    }

    private static func readAlerts(_ defaults: UserDefaults) -> AlertPreferences {
        func flag(_ name: String) -> Bool {
            defaults.object(forKey: key(name)) as? Bool ?? true
        }
        var alerts = AlertPreferences()
        alerts.radarFixed = flag("radarFixed")
        if let stored = defaults.stringArray(forKey: key("hiddenReports")) {
            alerts.hiddenReports = Set(stored.compactMap { ReportType(rawValue: $0) })
        } else {
            // Before one switch per category: the grouped switches of earlier builds.
            var hidden = Set<ReportType>()
            if !flag("radarMobile") { hidden.insert(.radarMobile) }
            if !flag("cameras") { hidden.insert(.camera) }
            if !flag("controlZones") { hidden.insert(.controlZone) }
            if !flag("hazards") {
                hidden.formUnion([.stoppedVehicle, .accident, .objectOnRoad, .damagedRoad, .roadworks, .slipperyRoad, .lowVisibility, .roadCrew, .wrongWay])
            }
            alerts.hiddenReports = hidden
        }
        alerts.sound = flag("sound")
        alerts.vibration = flag("vibration")
        alerts.voice = flag("voice")
        alerts.overspeed = OverspeedWarning(rawValue: defaults.string(forKey: key("overspeed")) ?? "") ?? .voice
        alerts.guidanceVolume = volume(defaults, "guidanceVolume")
        alerts.alertVolume = volume(defaults, "alertVolume")
        return alerts
    }

    /// Stored values, tolerant of anything an older build wrote.
    private static func readSettings(_ defaults: UserDefaults) -> AppSettings {
        var settings = AppSettings()
        settings.theme = AppTheme(rawValue: defaults.string(forKey: key("theme")) ?? "") ?? legacyTheme(defaults)
        settings.accent = AccentColor(rawValue: defaults.string(forKey: key("accent")) ?? "") ?? .cyan
        settings.avoidTolls = defaults.object(forKey: key("avoidTolls")) as? Bool ?? false
        settings.avoidHighways = defaults.object(forKey: key("avoidHighways")) as? Bool ?? false
        settings.avoidTraffic = defaults.object(forKey: key("avoidTraffic")) as? Bool ?? false
        settings.preferredFuel = FuelType(rawValue: defaults.string(forKey: key("preferredFuel")) ?? "") ?? .gazole
        settings.fuelNearestOnly = defaults.object(forKey: key("fuelNearestOnly")) as? Bool ?? false
        settings.sharedTraffic = defaults.object(forKey: key("shareSlowdowns")) as? Bool ?? true
        settings.tripSuggestions = defaults.object(forKey: key("tripSuggestions")) as? Bool ?? true
        settings.drivingStats = defaults.object(forKey: key("drivingStats")) as? Bool ?? true
        settings.presence = defaults.object(forKey: key("presence")) as? Bool ?? false
        settings.usageTime = defaults.object(forKey: key("usageTime")) as? Bool ?? true
        settings.presenceAsked = defaults.object(forKey: key("presenceAsked")) as? Bool ?? false
        return settings
    }

    /// A stored volume, full when missing or out of range.
    private static func volume(_ defaults: UserDefaults, _ name: String) -> Double {
        guard let value = defaults.object(forKey: key(name)) as? Double, (0...1).contains(value) else { return 1 }
        return value
    }

    /// Before "Thème général": the basemap setting was what the drive showed, so it decides.
    private static func legacyTheme(_ defaults: UserDefaults) -> AppTheme {
        switch defaults.string(forKey: key("mapStyle")) {
        case "bright": .day
        case "dark": .night
        default: .auto
        }
    }
}
