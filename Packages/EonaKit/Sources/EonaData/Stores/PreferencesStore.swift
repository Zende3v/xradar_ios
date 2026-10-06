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

/// Thème accent : onze teintes historiques et quatre palettes. Clés existantes conservées.
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
    case pastels = "eona-pastels"
    case mineral = "eona-mineral"
    case opal = "eona-opal"
    case dusk = "eona-dusk"

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
        case .pastels: "Pastels EONA+"
        case .mineral: "Minéral"
        case .opal: "Opale"
        case .dusk: "Crépuscule"
        }
    }

    /// Accent principal pour texte courant et guidage.
    public var value: UInt32 {
        switch self {
        case .pastels: 0x9FCAF1
        case .mineral: 0x9CC0AC
        case .opal: 0x91D7CB
        case .dusk: 0xE8B087
        default: UInt32(rawValue, radix: 16) ?? 0x2CD5E0
        }
    }

    public var isMulticolour: Bool { Self.palettes.contains(self) }

    /// Unicolores et Opale gratuits ; trois autres palettes réservées EONA+ et essai actif.
    public var requiresPlus: Bool { self == .pastels || self == .mineral || self == .dusk }

    /// Pastels EONA+, Minéral, Opale et Crépuscule. Mélanges sobres, trois teintes distinctes par ajout.
    public var paletteValues: [UInt32] {
        switch self {
        case .pastels: [0x9FCAF1, 0xBDB2EE, 0xE6AED3, 0xF1C0A7, 0xACD9C9]
        case .mineral: [0x9CC0AC, 0xE2B56E, 0xB0B5BB]
        case .opal: [0x91D7CB, 0x9BBBE6, 0xE7E1D4]
        case .dusk: [0xE8B087, 0xD19CAC, 0xAEA3D7]
        default: [value]
        }
    }

    /// Trois teintes distinctes sur petits contrôles et curseur. Palette complète conservée.
    public var controlPaletteValues: [UInt32] {
        switch self {
        case .pastels: [0x9FCAF1, 0xE6AED3, 0xF1C0A7]
        case .mineral, .opal, .dusk: paletteValues
        default: [value]
        }
    }

    /// Garde contraste sur carte claire pour nouvelles palettes douces.
    public var routeValue: UInt32 {
        switch self {
        case .pastels: 0x5A8FB8
        case .mineral: 0x71957E
        case .opal: 0x4A968E
        case .dusk: 0xA56D4D
        default: value
        }
    }

    public static var unicolours: [AccentColor] { allCases.filter { !$0.isMulticolour } }
    public static let palettes: [AccentColor] = [.pastels, .mineral, .opal, .dusk]
}

/// « Réglages ▸ Véhicule » : le curseur du conducteur sur la carte. Scooter 50 et sans permis
/// changent aussi l'itinéraire (45 km/h, sans voie rapide) et les limites affichées. Gardé sur ce
/// téléphone, jamais envoyé.
public enum VehicleType: String, Sendable, Hashable, CaseIterable {
    case arrow
    case car
    case motorcycle
    case taxi
    case truck
    case scooter50
    case licenseFree

    public var label: String {
        switch self {
        case .arrow: "Flèche"
        case .car: "Voiture"
        case .motorcycle: "Moto"
        case .taxi: "Taxi"
        case .truck: "Camion"
        case .scooter50: "Scooter 50"
        case .licenseFree: "Sans permis"
        }
    }

    /// Cyclomoteur ou voiturette : itinéraire « moped » du backend.
    public var moped: Bool {
        self == .scooter50 || self == .licenseFree
    }

    public var requiresPlus: Bool { self == .taxi || self == .truck }

    public var routingVehicle: String {
        moped ? "moped" : self == .taxi ? "taxi" : "car"
    }

    /// Vitesse maximale du véhicule (Code de la route, R311-1) ; nil : limites de la route seules.
    public var speedCapKmh: Int? {
        moped ? 45 : nil
    }
}

/// Look-and-feel and routing choices, edited from Réglages and the trip menu.
public struct AppSettings: Sendable, Hashable {
    public var theme: AppTheme = .auto
    public var accent: AccentColor = .opal
    /// Ask the router to keep the trip off toll roads.
    public var avoidTolls = false
    /// Ask the router to keep the trip off motorways.
    public var avoidHighways = false
    /// Ask the router to keep the trip off ferries (D4.2).
    public var avoidFerries = false
    /// Fuel whose price the nearby "Carburant" search shows, picked there or in Réglages (Gazole by default).
    public var preferredFuel: FuelType = .gazole
    /// "Proche uniquement" in the nearby "Carburant" search: the nearest open stations, no price.
    public var fuelNearestOnly = false
    /// « Consommation » (L/100 km) : coût carburant estimé du choix d'itinéraire.
    public var consumption = AppSettings.defaultConsumption
    /// « Permis probatoire » : limitations jeune conducteur affichées et alertes (ProbationaryLimits).
    public var probationary = false
    /// « Protection pluie » : écran verrouillé au-delà de 15 km/h, contre les gouttes.
    public var rainLock = false
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
    /// EONA team sees where this driver is. On by default since build 28; the driver can turn it off.
    public var presence = true
    /// "Temps d'utilisation": the time spent with the app open adds up on the account.
    public var usageTime = true
    /// True once the driver has answered the question about sharing their position: the app asks
    /// once, then never again.
    public var presenceAsked = false
    /// The version of the terms the driver accepted, and when. Empty: never accepted.
    public var termsVersion = ""
    public var termsAcceptedAt: Date?
    /// True when the driver refused the terms: the app stays closed until they change their mind.
    public var termsDeclined = false

    public init() {}

    /// Valeur de départ, à régler par le conducteur.
    public static let defaultConsumption = 6.5
    /// Curseur des Réglages : 1,0 à 30,0 L/100 km, cran de 0,1.
    public static let consumptionRange = 1.0...30.0
}

/// App preferences, one UserDefaults key per value like the Android SharedPreferences.
@MainActor
@Observable
public final class PreferencesStore {
    public private(set) var alerts: AlertPreferences
    public private(set) var settings: AppSettings
    /// Apart from [settings]: picking a vehicle must not wake what watches them (the route
    /// options among others).
    public private(set) var vehicleType: VehicleType

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        alerts = Self.readAlerts(defaults)
        settings = Self.readSettings(defaults)
        // Missing or unknown: the navigation arrow. Keep saved vehicle choices.
        vehicleType = VehicleType(rawValue: defaults.string(forKey: Self.key("vehicleType")) ?? "") ?? .arrow
    }

    public func setVehicleType(_ type: VehicleType) {
        vehicleType = type
        defaults.set(type.rawValue, forKey: Self.key("vehicleType"))
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

    /// The driver accepted [version] of the terms, now. Any earlier refusal is forgotten.
    public func acceptTerms(version: String) {
        updateSettings {
            $0.termsVersion = version
            $0.termsAcceptedAt = Date()
            $0.termsDeclined = false
        }
    }

    /// The driver refused: nothing that needs the terms starts, and the screen says why.
    public func declineTerms() {
        updateSettings {
            $0.termsDeclined = true
            $0.termsVersion = ""
            $0.termsAcceptedAt = nil
        }
    }

    /// Whether the terms must be shown: never accepted, refused, or a version that has to be
    /// agreed to again (a typo fixed in 1.0.1 does not ask anyone a second time).
    public func needsTerms(required: String) -> Bool {
        if settings.termsDeclined { return true }
        let accepted = settings.termsVersion
        guard !accepted.isEmpty else { return true }
        return major(accepted) != major(required)
    }

    /// "1.4.2" → "1": only a new first number asks again.
    private func major(_ version: String) -> String {
        version.split(separator: ".").first.map(String.init) ?? version
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
        defaults.set(updated.avoidFerries, forKey: Self.key("avoidFerries"))
        defaults.set(updated.preferredFuel.rawValue, forKey: Self.key("preferredFuel"))
        defaults.set(updated.fuelNearestOnly, forKey: Self.key("fuelNearestOnly"))
        defaults.set(updated.consumption, forKey: Self.key("consumption"))
        defaults.set(updated.probationary, forKey: Self.key("probationary"))
        defaults.set(updated.rainLock, forKey: Self.key("rainLock"))
        // Stored under its first name: the choice made before the rename stays.
        defaults.set(updated.sharedTraffic, forKey: Self.key("shareSlowdowns"))
        defaults.set(updated.tripSuggestions, forKey: Self.key("tripSuggestions"))
        defaults.set(updated.drivingStats, forKey: Self.key("drivingStats"))
        defaults.set(updated.presence, forKey: Self.key("presence"))
        defaults.set(updated.usageTime, forKey: Self.key("usageTime"))
        defaults.set(updated.presenceAsked, forKey: Self.key("presenceAsked"))
        defaults.set(updated.termsVersion, forKey: Self.key("termsVersion"))
        defaults.set(updated.termsAcceptedAt, forKey: Self.key("termsAcceptedAt"))
        defaults.set(updated.termsDeclined, forKey: Self.key("termsDeclined"))
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
        settings.accent = AccentColor(rawValue: defaults.string(forKey: key("accent")) ?? "") ?? .opal
        settings.avoidTolls = defaults.object(forKey: key("avoidTolls")) as? Bool ?? false
        settings.avoidHighways = defaults.object(forKey: key("avoidHighways")) as? Bool ?? false
        settings.avoidFerries = defaults.object(forKey: key("avoidFerries")) as? Bool ?? false
        settings.preferredFuel = FuelType(rawValue: defaults.string(forKey: key("preferredFuel")) ?? "") ?? .gazole
        settings.fuelNearestOnly = defaults.object(forKey: key("fuelNearestOnly")) as? Bool ?? false
        if let litres = defaults.object(forKey: key("consumption")) as? Double, AppSettings.consumptionRange.contains(litres) {
            settings.consumption = litres
        }
        settings.probationary = defaults.object(forKey: key("probationary")) as? Bool ?? false
        settings.rainLock = defaults.object(forKey: key("rainLock")) as? Bool ?? false
        settings.sharedTraffic = defaults.object(forKey: key("shareSlowdowns")) as? Bool ?? true
        settings.tripSuggestions = defaults.object(forKey: key("tripSuggestions")) as? Bool ?? true
        settings.drivingStats = defaults.object(forKey: key("drivingStats")) as? Bool ?? true
        // Activée d'office une fois (build 28), même coupée avant ; un refus ensuite reste.
        if defaults.object(forKey: key("presenceOnByDefault")) == nil {
            defaults.set(true, forKey: key("presence"))
            defaults.set(true, forKey: key("presenceOnByDefault"))
        }
        settings.presence = defaults.object(forKey: key("presence")) as? Bool ?? true
        settings.usageTime = defaults.object(forKey: key("usageTime")) as? Bool ?? true
        settings.presenceAsked = defaults.object(forKey: key("presenceAsked")) as? Bool ?? false
        settings.termsVersion = defaults.string(forKey: key("termsVersion")) ?? ""
        settings.termsAcceptedAt = defaults.object(forKey: key("termsAcceptedAt")) as? Date
        settings.termsDeclined = defaults.object(forKey: key("termsDeclined")) as? Bool ?? false
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
