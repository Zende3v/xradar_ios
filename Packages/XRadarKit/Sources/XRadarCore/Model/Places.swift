/// How a place surfaces in search (drives its icon in the UI).
public enum PlaceKind: Sendable, Hashable {
    case home
    case work
    case favorite
    case recent
    case result
}

/// A category of nearby place the driver can jump to from the search screen. The raw value is
/// what the backend maps to an OpenStreetMap tag.
public enum PlaceCategory: String, Sendable, Hashable, CaseIterable {
    case fuel
    case charging
    case parking
    case tobacco
    case garage
    case hotel
    case atm

    public var label: String {
        switch self {
        case .fuel: "Carburant"
        case .charging: "Bornes"
        case .parking: "Parking"
        case .tobacco: "Tabac"
        case .garage: "Garage"
        case .hotel: "Hôtel"
        case .atm: "Retrait"
        }
    }
}

/// A searchable or known destination, reused by search and routing.
public struct Place: Sendable, Hashable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let kind: PlaceKind
    public let lat: Double
    public let lon: Double
    /// Official fuel prices, only for a fuel station found by the nearby search.
    public let fuel: StationFuel?
    /// Distance from the search point, for places found by the nearby search; else nil.
    public let distanceMeters: Int?
    /// Hours, charger, car park… for places found by the nearby search; else nil.
    public let nearby: NearbyInfo?

    public init(
        id: String,
        name: String,
        subtitle: String,
        kind: PlaceKind,
        lat: Double,
        lon: Double,
        fuel: StationFuel? = nil,
        distanceMeters: Int? = nil,
        nearby: NearbyInfo? = nil
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.kind = kind
        self.lat = lat
        self.lon = lon
        self.fuel = fuel
        self.distanceMeters = distanceMeters
        self.nearby = nearby
    }
}

/// Whether a place is open right now, as the backend read its hours.
public enum OpenState: Sendable, Hashable {
    case open
    case closed
    case unknown
}

/// One opening slot of the day, "07:00" to "12:00" ("24:00" for midnight).
public struct TimeSlot: Sendable, Hashable {
    public let from: String
    public let to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

public struct OpeningHours: Sendable, Hashable {
    public let state: OpenState
    /// Open with no change ahead: 24/7.
    public let alwaysOpen: Bool
    /// Today's opening slots.
    public let today: [TimeSlot]
    /// When [state] changes next (epoch millis), within a week; nil otherwise.
    public let nextChangeMillis: Int?
    /// True when the hours come from the official fuel feed rather than OpenStreetMap.
    public let official: Bool

    public init(state: OpenState, alwaysOpen: Bool, today: [TimeSlot], nextChangeMillis: Int?, official: Bool = false) {
        self.state = state
        self.alwaysOpen = alwaysOpen
        self.today = today
        self.nextChangeMillis = nextChangeMillis
        self.official = official
    }
}

public struct ChargingInfo: Sendable, Hashable {
    /// Strongest charging power, kW.
    public let maxKw: Double?
    /// "CCS", "CHAdeMO", "Type 2"… strongest first.
    public let connectors: [String]
    /// Charging points.
    public let points: Int?

    public init(maxKw: Double?, connectors: [String], points: Int?) {
        self.maxKw = maxKw
        self.connectors = connectors
        self.points = points
    }
}

public enum ParkingType: Sendable, Hashable {
    case underground
    case multiStorey
    case rooftop
    case surface
    case streetSide
}

public struct ParkingInfo: Sendable, Hashable {
    /// true: paying, false: free, nil: unknown.
    public let fee: Bool?
    public let type: ParkingType?
    public let capacity: Int?
    public let parkAndRide: Bool

    public init(fee: Bool?, type: ParkingType?, capacity: Int?, parkAndRide: Bool) {
        self.fee = fee
        self.type = type
        self.capacity = capacity
        self.parkAndRide = parkAndRide
    }
}

/// What the nearby search knows about a place beyond its name.
public struct NearbyInfo: Sendable, Hashable {
    public let brand: String?
    public let hours: OpeningHours?
    /// Reserved for the customers of a shop or a hotel.
    public let customersOnly: Bool
    public let charging: ChargingInfo?
    public let parking: ParkingInfo?
    public let stars: Int?

    public init(
        brand: String? = nil,
        hours: OpeningHours? = nil,
        customersOnly: Bool = false,
        charging: ChargingInfo? = nil,
        parking: ParkingInfo? = nil,
        stars: Int? = nil
    ) {
        self.brand = brand
        self.hours = hours
        self.customersOnly = customersOnly
        self.charging = charging
        self.parking = parking
        self.stars = stars
    }
}
