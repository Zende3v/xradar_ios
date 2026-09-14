/// The limits a driver can propose: the same values the map draws as signs.
public enum SpeedLimits {
    public static let values: [Int] = [20, 30, 50, 70, 80, 90, 100, 110, 130]
}

/// Where the limit shown on the HUD comes from, sent along with a proposal.
public enum SpeedLimitSource: String, Sendable, Hashable {
    /// The road's own limit: OSM, or a change drivers validated.
    case road = "map"
    /// The VMA of the speed radar ahead, where the road has no limit mapped.
    case radar
}

/// A proposed change of the limit at one spot, as the backend tracks it: [oldKmh] (nil when
/// nothing was known there) becomes [newKmh] once enough drivers agree.
public struct SpeedLimitChange: Sendable, Hashable {
    public enum Status: String, Sendable, Hashable {
        case pending
        case validated
        /// Expired, outdated, rejected, superseded or removed.
        case closed

        public static func fromWire(_ value: String?) -> Status {
            value.flatMap(Status.init(rawValue:)) ?? .closed
        }
    }

    public let id: String
    public let status: Status
    public let oldKmh: Int?
    /// The limit now applied there, once [status] is validated.
    public let newKmh: Int?
    /// People whose proposal still counts there, and how many a change needs at least.
    public let reporters: Int
    public let required: Int

    public init(id: String, status: Status, oldKmh: Int?, newKmh: Int?, reporters: Int, required: Int) {
        self.id = id
        self.status = status
        self.oldKmh = oldKmh
        self.newKmh = newKmh
        self.reporters = reporters
        self.required = required
    }
}
