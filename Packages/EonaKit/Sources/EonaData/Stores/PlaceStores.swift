import Foundation
import Observation
import EonaCore

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
///
/// A copy is kept outside the app's own storage — the Keychain, on the phone — where the
/// session already lives. An update that arrives with a fresh app container used to find the
/// account again but no recents; it now finds both. Turning "Suggestions de trajets" off
/// erases the copy with the list.
@MainActor
@Observable
public final class RecentsStore {
    public static let limit = 8

    public private(set) var recents: [Place]

    private let defaults: UserDefaults
    private let backup: (any SecretStore)?

    public init(defaults: UserDefaults = .standard, backup: (any SecretStore)? = nil) {
        self.defaults = defaults
        self.backup = backup
        if let stored = defaults.decoded([StoredPlace].self, forKey: Keys.list) {
            recents = stored.map { $0.place(kind: .recent) }
            // Recents kept before the copy existed get one now.
            if !stored.isEmpty, backup?.string(for: Keys.backup) == nil {
                Self.save(stored, to: backup)
            }
        } else if let stored = Self.restore(from: backup) {
            // A fresh container: the list comes back from the copy, and is written again.
            recents = stored.map { $0.place(kind: .recent) }
            defaults.encode(stored, forKey: Keys.list)
        } else {
            recents = []
        }
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
        Self.save(stored, to: backup)
        recents = stored.map { $0.place(kind: .recent) }
    }

    /// The copy follows the list; an empty list leaves no copy behind.
    private static func save(_ stored: [StoredPlace], to backup: (any SecretStore)?) {
        guard let backup else { return }
        guard !stored.isEmpty, let data = try? JSONEncoder().encode(stored) else {
            backup.set(nil, for: Keys.backup)
            return
        }
        backup.set(String(data: data, encoding: .utf8), for: Keys.backup)
    }

    private static func restore(from backup: (any SecretStore)?) -> [StoredPlace]? {
        guard let text = backup?.string(for: Keys.backup),
              let stored = try? JSONDecoder().decode([StoredPlace].self, from: Data(text.utf8)),
              !stored.isEmpty
        else { return nil }
        return stored
    }

    private enum Keys {
        static let list = "xr_recents.list"
        static let backup = "xr_recents.backup"
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
