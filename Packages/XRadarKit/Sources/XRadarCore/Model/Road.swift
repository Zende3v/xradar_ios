/// Kind of road event. Colors and icons are assigned in the UI layer.
public enum AlertType: Sendable, Hashable, CaseIterable {
    case radarFixed
    case radarMobile
    case controlZone
    case camera
    case hazard
    case accident
    case roadwork
    case radarCar
}

/// A single road event surfaced to the driver.
public struct RoadAlert: Sendable, Hashable {
    public let type: AlertType
    public let title: String
    public let roadLabel: String?
    public let speedLimitKmh: Int?
    public let distanceMeters: Int
    public let etaSeconds: Int
    /// 0...1 confidence in this event.
    public let confidence: Double
    /// For crowdsourced events (e.g. control zones): when it was last reported.
    public let lastReportedLabel: String?
    /// Stable id of the source radar/report, for voice-announcement de-duplication.
    public let id: String?

    public init(
        type: AlertType,
        title: String,
        roadLabel: String?,
        speedLimitKmh: Int?,
        distanceMeters: Int,
        etaSeconds: Int,
        confidence: Double,
        lastReportedLabel: String?,
        id: String? = nil
    ) {
        self.type = type
        self.title = title
        self.roadLabel = roadLabel
        self.speedLimitKmh = speedLimitKmh
        self.distanceMeters = distanceMeters
        self.etaSeconds = etaSeconds
        self.confidence = confidence
        self.lastReportedLabel = lastReportedLabel
        self.id = id
    }
}

/// A fixed radar from the official dataset. [code] is the source type (ETF/ETD/ETU speed
/// radars, ETFR red-light…).
public struct Radar: Sendable, Hashable {
    public let id: String
    public let code: String
    public let vma: Int?
    public let lat: Double
    public let lon: Double

    public init(id: String, code: String, vma: Int?, lat: Double, lon: Double) {
        self.id = id
        self.code = code
        self.vma = vma
        self.lat = lat
        self.lon = lon
    }

    public var isSpeedRadar: Bool {
        !code.uppercased().hasPrefix("ETFR")
    }

    public var alertType: AlertType {
        isSpeedRadar ? .radarFixed : .camera
    }

    public var displayTitle: String {
        isSpeedRadar ? "Radar fixe" : "Radar feu rouge"
    }
}

/// A probable radar-car zone, aggregated server-side from admin plate reports. The circle
/// tightens ([radiusMeters] shrinks) as more reports corroborate it. The plate never leaves
/// the server.
public struct RadarZone: Sendable, Hashable {
    public let id: String
    public let lat: Double
    public let lon: Double
    public let radiusMeters: Double
    public let count: Int

    public init(id: String, lat: Double, lon: Double, radiusMeters: Double, count: Int) {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.radiusMeters = radiusMeters
        self.count = count
    }
}

/// A road sign or feature from OpenStreetMap; the raw value is the backend's name for it.
public enum SignType: String, Sendable, Hashable, CaseIterable {
    case trafficSignals = "traffic_signals"
    case stop
    case giveWay = "give_way"
    case crossing
    case roundabout
    case construction
    case noEntry = "no_entry"
    /// SNCF level crossing (croix de Saint-André).
    case levelCrossing = "level_crossing"
    case speedLimit = "speed"
}

public struct RoadSign: Sendable, Hashable {
    public let type: SignType
    public let lat: Double
    public let lon: Double
    public let speed: Int?

    public init(type: SignType, lat: Double, lon: Double, speed: Int? = nil) {
        self.type = type
        self.lat = lat
        self.lon = lon
        self.speed = speed
    }
}
