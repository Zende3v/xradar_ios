import Foundation
import Observation
import XRadarCore

/// User-tunable alert preferences, edited from the trip menu and read to filter alerts.
public struct AlertPreferences: Sendable, Hashable {
    public static let minLiveKm = 1
    public static let maxLiveKm = 200

    public var radarFixed = true
    public var radarMobile = true
    public var cameras = true
    public var controlZones = true
    public var hazards = true
    public var sound = true
    public var vibration = true
    /// Spoken alert and maneuver announcements.
    public var voice = true
    /// Share my position with nearby drivers (visible by default).
    public var liveVisible = true
    /// Radius (km) to see other live drivers (1...200).
    public var liveRadiusKm = 20

    public init() {}
}

/// How the app picks its color scheme.
public enum ThemeMode: String, Sendable, Hashable, CaseIterable {
    case system
    case light
    case dark
}

/// Which basemap the map draws: follow the app theme, or force one.
public enum MapStyle: String, Sendable, Hashable, CaseIterable {
    case auto
    case bright
    case dark
}

/// Look-and-feel and routing choices, edited from Réglages and the trip menu.
public struct AppSettings: Sendable, Hashable {
    public var themeMode: ThemeMode = .dark
    public var mapStyle: MapStyle = .auto
    /// Ask the router to keep the trip off toll roads.
    public var avoidTolls = false
    /// Ask the router to keep the trip off motorways.
    public var avoidHighways = false
    /// Fuel whose price the nearby "Carburant" search shows, picked there.
    public var preferredFuel: FuelType = .gazole

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
        defaults.set(updated.radarMobile, forKey: Self.key("radarMobile"))
        defaults.set(updated.cameras, forKey: Self.key("cameras"))
        defaults.set(updated.controlZones, forKey: Self.key("controlZones"))
        defaults.set(updated.hazards, forKey: Self.key("hazards"))
        defaults.set(updated.sound, forKey: Self.key("sound"))
        defaults.set(updated.vibration, forKey: Self.key("vibration"))
        defaults.set(updated.voice, forKey: Self.key("voice"))
        defaults.set(updated.liveVisible, forKey: Self.key("liveVisible"))
        defaults.set(updated.liveRadiusKm, forKey: Self.key("liveRadiusKm"))
    }

    public func updateSettings(_ change: (inout AppSettings) -> Void) {
        var updated = settings
        change(&updated)
        settings = updated
        defaults.set(updated.themeMode.rawValue, forKey: Self.key("themeMode"))
        defaults.set(updated.mapStyle.rawValue, forKey: Self.key("mapStyle"))
        defaults.set(updated.avoidTolls, forKey: Self.key("avoidTolls"))
        defaults.set(updated.avoidHighways, forKey: Self.key("avoidHighways"))
        defaults.set(updated.preferredFuel.rawValue, forKey: Self.key("preferredFuel"))
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
        alerts.radarMobile = flag("radarMobile")
        alerts.cameras = flag("cameras")
        alerts.controlZones = flag("controlZones")
        alerts.hazards = flag("hazards")
        alerts.sound = flag("sound")
        alerts.vibration = flag("vibration")
        alerts.voice = flag("voice")
        alerts.liveVisible = flag("liveVisible")
        let radius = defaults.object(forKey: key("liveRadiusKm")) as? Int ?? 20
        alerts.liveRadiusKm = min(max(radius, AlertPreferences.minLiveKm), AlertPreferences.maxLiveKm)
        return alerts
    }

    /// Stored values, tolerant of anything an older build wrote.
    private static func readSettings(_ defaults: UserDefaults) -> AppSettings {
        var settings = AppSettings()
        settings.themeMode = ThemeMode(rawValue: defaults.string(forKey: key("themeMode")) ?? "") ?? .dark
        settings.mapStyle = MapStyle(rawValue: defaults.string(forKey: key("mapStyle")) ?? "") ?? .auto
        settings.avoidTolls = defaults.object(forKey: key("avoidTolls")) as? Bool ?? false
        settings.avoidHighways = defaults.object(forKey: key("avoidHighways")) as? Bool ?? false
        settings.preferredFuel = FuelType(rawValue: defaults.string(forKey: key("preferredFuel")) ?? "") ?? .gazole
        return settings
    }
}
