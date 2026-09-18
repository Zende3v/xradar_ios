import Foundation
import Observation
import XRadarCore

/// A trip kept as a favourite: where to, and optionally where from (simulated start).
public struct FavoriteTrip: Sendable, Hashable {
    public let to: Place
    public let from: Place?

    public init(to: Place, from: Place? = nil) {
        self.to = to
        self.from = from
    }

    public var id: String {
        from.map { "\($0.id)>\(to.id)" } ?? to.id
    }
}

/// Home, work and favourite trips, on the phone (UserDefaults + JSON).
@MainActor
@Observable
public final class SavedPlacesStore {
    public static let maxFavorites = 12

    public private(set) var home: Place?
    public private(set) var work: Place?
    public private(set) var favorites: [FavoriteTrip]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        home = defaults.decoded(StoredPlace.self, forKey: Keys.home)?.place(kind: .home)
        work = defaults.decoded(StoredPlace.self, forKey: Keys.work)?.place(kind: .work)
        favorites = (defaults.decoded([StoredFavorite].self, forKey: Keys.favorites) ?? []).map {
            FavoriteTrip(to: $0.to.place(kind: .favorite), from: $0.from?.place(kind: .result))
        }
    }

    public func setHome(_ place: Place?) {
        defaults.encode(place.map { StoredPlace($0) }, forKey: Keys.home)
        home = place?.with(kind: .home, name: "Maison")
    }

    public func setWork(_ place: Place?) {
        defaults.encode(place.map { StoredPlace($0) }, forKey: Keys.work)
        work = place?.with(kind: .work, name: "Travail")
    }

    public func toggleFavorite(_ trip: FavoriteTrip) {
        let updated = favorites.contains { $0.id == trip.id }
            ? favorites.filter { $0.id != trip.id }
            : Array(([trip] + favorites).prefix(Self.maxFavorites))
        defaults.encode(updated.map { favorite in StoredFavorite(to: StoredPlace(favorite.to), from: favorite.from.map { StoredPlace($0) }) }, forKey: Keys.favorites)
        favorites = updated
    }

    public func isFavorite(_ id: String) -> Bool {
        favorites.contains { $0.id == id }
    }

    private enum Keys {
        static let home = "xr_saved_places.home"
        static let work = "xr_saved_places.work"
        static let favorites = "xr_saved_places.favorites"
    }
}

/// Recently chosen destinations, newest first.
@MainActor
@Observable
public final class RecentsStore {
    public static let limit = 8

    public private(set) var recents: [Place]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recents = (defaults.decoded([StoredPlace].self, forKey: Keys.list) ?? []).map { $0.place(kind: .recent) }
    }

    public func add(_ place: Place) {
        write(Array(([place] + recents.filter { $0.id != place.id }).prefix(Self.limit)))
    }

    /// Drop one entry from the list (the ✕ on a row).
    /// "Suggestions de trajets" turned off: nothing is kept any more.
    public func clear() {
        write([])
    }

    public func remove(_ id: String) {
        write(recents.filter { $0.id != id })
    }

    private func write(_ places: [Place]) {
        let stored = places.map { StoredPlace($0) }
        defaults.encode(stored, forKey: Keys.list)
        recents = stored.map { $0.place(kind: .recent) }
    }

    private enum Keys {
        static let list = "xr_recents.list"
    }
}

/// A place as saved on the phone: only what identifies it and where it is.
struct StoredPlace: Codable {
    let id: String
    let name: String
    let subtitle: String
    let lat: Double
    let lon: Double

    init(_ place: Place) {
        id = place.id
        name = place.name
        subtitle = place.subtitle
        lat = place.lat
        lon = place.lon
    }

    func place(kind: PlaceKind) -> Place {
        Place(id: id, name: name, subtitle: subtitle, kind: kind, lat: lat, lon: lon)
    }
}

struct StoredFavorite: Codable {
    let to: StoredPlace
    let from: StoredPlace?
}

extension Place {
    func with(kind: PlaceKind, name newName: String) -> Place {
        Place(id: id, name: newName, subtitle: subtitle, kind: kind, lat: lat, lon: lon, fuel: fuel, distanceMeters: distanceMeters, nearby: nearby)
    }
}

extension UserDefaults {
    func decoded<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Saves [value] as JSON; nil removes the key.
    func encode<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            removeObject(forKey: key)
            return
        }
        set(data, forKey: key)
    }
}
