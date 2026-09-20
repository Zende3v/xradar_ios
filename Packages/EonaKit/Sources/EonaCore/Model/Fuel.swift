import Foundation

/// A fuel as the official feed (prix-carburants.gouv.fr) names it; the raw value is its name
/// on the wire.
public enum FuelType: String, Sendable, Hashable, CaseIterable {
    case gazole = "Gazole"
    case sp95 = "SP95"
    case sp98 = "SP98"
    case e10 = "E10"
    case e85 = "E85"
    case gplc = "GPLc"

    public var label: String {
        rawValue
    }
}

/// One official price at a station.
public struct FuelPrice: Sendable, Hashable {
    /// Only a price the station updated within this many millis (48 h) is shown.
    public static let freshMillis = 48 * 60 * 60 * 1000

    public let type: FuelType
    /// Euros per litre.
    public let euros: Double
    /// When the station last updated it, ISO-8601 with offset; nil when unknown.
    public let updatedAt: String?
    /// The station reports this fuel as not on sale right now.
    public let outOfStock: Bool
    /// [updatedAt] as epoch millis, or nil when missing or unreadable.
    public let updatedAtMillis: Int?

    public init(type: FuelType, euros: Double, updatedAt: String?, outOfStock: Bool = false) {
        self.type = type
        self.euros = euros
        self.updatedAt = updatedAt
        self.outOfStock = outOfStock
        updatedAtMillis = isoEpochMillis(updatedAt)
    }

    /// An older price counts as unknown.
    public func isFresh(nowMillis: Int) -> Bool {
        guard let at = updatedAtMillis else { return false }
        return nowMillis - at <= Self.freshMillis
    }

    /// "2,283 €": three decimals, as the official feed gives them.
    public var priceLabel: String {
        "\(frenchDecimal(euros, places: 3)) €"
    }

    /// "à l'instant", "il y a 12 min", "il y a 3 h", "il y a 1 j": how old the price is; nil
    /// when its date is unknown.
    public func ageLabel(nowMillis: Int) -> String? {
        guard let at = updatedAtMillis else { return nil }
        let minutes = max((nowMillis - at) / 60_000, 0)
        if minutes < 1 { return "à l'instant" }
        if minutes < 60 { return "il y a \(minutes) min" }
        if minutes < 24 * 60 { return "il y a \(minutes / 60) h" }
        return "il y a \(minutes / (24 * 60)) j"
    }

}

/// The official prices matched to a station found by the nearby search. [matchedBy] is "id"
/// (OpenStreetMap carries the official id) or "position" (unambiguous nearest).
public struct StationFuel: Sendable, Hashable {
    public let stationId: String
    public let matchedBy: String
    public let prices: [FuelPrice]

    public init(stationId: String, matchedBy: String, prices: [FuelPrice]) {
        self.stationId = stationId
        self.matchedBy = matchedBy
        self.prices = prices
    }
}

extension Place {
    /// A price for [fuel] is on show at this station: on sale, and updated within 48 h.
    public func showsFuelPrice(_ fuel: FuelType, nowMillis: Int) -> Bool {
        shownFuelPrice(fuel, nowMillis: nowMillis) != nil
    }

    /// The price on show for [fuel] (see [showsFuelPrice]), in euros per litre; nil when none.
    public func shownFuelPrice(_ fuel: FuelType, nowMillis: Int) -> Double? {
        self.fuel?.prices.first { $0.type == fuel && !$0.outOfStock && $0.isFresh(nowMillis: nowMillis) }?.euros
    }
}

/// Which stations the "Carburant" search lists, out of the pool the backend sends (its 60
/// nearest stations; [NearbyPicker] passes only those not closed right now).
///
/// In a city (the [limit] nearest stations all within [denseReachMeters]) the nearest
/// stations that show a price for the chosen fuel come first, as long as they stay within
/// [pricedStretch] times that reach; the list is then topped up with the nearest others.
/// Anywhere sparser it is simply the [limit] nearest: no station is traded for a price there.
/// With a fuel chosen, the list goes cheapest first (then the stations without a price, nearest
/// first); without one ("Proche uniquement"), nearest first.
public enum FuelStationPicker {

    /// Stations listed.
    public static let limit = 20

    /// The 20th nearest station within this distance: a dense area, prices may pick.
    public static let denseReachMeters = 6_000

    /// A priced station may be picked up to this many times the 20th station's distance.
    public static let pricedStretch = 2

    public static func pick(_ pool: [Place], fuel: FuelType?, nowMillis: Int) -> [Place] {
        let nearest = pool.stableSorted { $0.distanceMeters ?? .max }
        guard let fuel else { return Array(nearest.prefix(limit)) }
        guard nearest.count > limit, let reach = nearest[limit - 1].distanceMeters, reach <= denseReachMeters else {
            return cheapestFirst(Array(nearest.prefix(limit)), fuel: fuel, nowMillis: nowMillis)
        }
        let cap = reach * pricedStretch
        let priced = Array(
            nearest
                .filter { ($0.distanceMeters ?? .max) <= cap && $0.showsFuelPrice(fuel, nowMillis: nowMillis) }
                .prefix(limit)
        )
        let pickedIds = Set(priced.map(\.id))
        let others = Array(nearest.filter { !pickedIds.contains($0.id) }.prefix(limit - priced.count))
        return cheapestFirst(priced + others, fuel: fuel, nowMillis: nowMillis)
    }

    /// The stations showing a price for [fuel], cheapest first (the nearer on a tie), then those
    /// without one, nearest first.
    static func cheapestFirst(_ stations: [Place], fuel: FuelType, nowMillis: Int) -> [Place] {
        let nearest = stations.stableSorted { $0.distanceMeters ?? .max }
        let priced = nearest.compactMap { place in place.shownFuelPrice(fuel, nowMillis: nowMillis).map { (place, $0) } }
        let cheapest = priced.enumerated()
            .sorted { $0.element.1 != $1.element.1 ? $0.element.1 < $1.element.1 : $0.offset < $1.offset }
            .map(\.element.0)
        return cheapest + nearest.filter { !$0.showsFuelPrice(fuel, nowMillis: nowMillis) }
    }
}
