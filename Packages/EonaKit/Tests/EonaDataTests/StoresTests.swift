import Foundation
import Testing
import EonaCore
@testable import EonaData

@MainActor
final class MemorySecrets: SecretStore {
    var values: [String: String] = [:]

    func string(for key: String) -> String? {
        values[key]
    }

    func set(_ value: String?, for key: String) {
        values[key] = value
    }
}

/// An empty UserDefaults of its own.
@MainActor
func freshDefaults() -> UserDefaults {
    let name = "eona-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
struct AccountStoreTests {
    static let accountBody = #"{"account":{"id":"u1","role":"guest","username":"neo","access":"trial"},"token":"t0k"}"#

    func store(_ transport: StubTransport, _ secrets: MemorySecrets, _ defaults: UserDefaults) -> AccountStore {
        AccountStore(api: AccountAPI(client: backend(transport)), secrets: secrets, defaults: defaults)
    }

    @Test func keepsTheSameDeviceId() {
        let secrets = MemorySecrets()
        let defaults = freshDefaults()
        let first = store(StubTransport(body: "{}"), secrets, defaults)
        first.restore()
        #expect(!first.deviceId.isEmpty)
        let second = store(StubTransport(body: "{}"), secrets, defaults)
        second.restore()
        #expect(second.deviceId == first.deviceId)
    }

    @Test func deviceSignInIsCachedForTheNextLaunch() async {
        let secrets = MemorySecrets()
        let defaults = freshDefaults()
        let transport = StubTransport(body: Self.accountBody)
        let account = store(transport, secrets, defaults)
        account.restore()
        await account.refresh()
        #expect(account.account?.username == "neo")
        #expect(account.token == "t0k")
        #expect(secrets.values["session_token"] == "t0k")
        #expect(transport.last?.path == "/api/accounts/auth")

        let relaunch = store(StubTransport(body: "{}"), secrets, defaults)
        relaunch.restore()
        #expect(relaunch.account?.username == "neo")
        #expect(relaunch.token == "t0k")
    }

    @Test func anExpiredTokenFallsBackToTheDevice() async {
        let secrets = MemorySecrets()
        secrets.values["session_token"] = "old"
        let body = Self.accountBody
        let transport = StubTransport { request in request.url?.path() == "/api/accounts/me" ? (401, "{}") : (200, body) }
        let account = store(transport, secrets, freshDefaults())
        account.restore()
        await account.refresh()
        #expect(account.token == "t0k")
        #expect(transport.last?.path == "/api/accounts/auth")
    }

    @Test func offlineKeepsTheCachedSession() async {
        let secrets = MemorySecrets()
        secrets.values["session_token"] = "old"
        let account = store(StubTransport { _ in throw URLError(.notConnectedToInternet) }, secrets, freshDefaults())
        account.restore()
        await account.refresh()
        #expect(account.token == "old")
    }

    @Test func revokedMemberSessionClearsCachedPrivileges() async throws {
        let secrets = MemorySecrets()
        let defaults = freshDefaults()
        let cached = AccountAPI.account(JSON(["id": "admin", "role": "admin", "access": "active", "canNavigate": true]))
        defaults.set(try JSONEncoder().encode(StoredAccount(cached)), forKey: "xr_identity.account")
        secrets.values["session_token"] = "revoked"
        let account = store(StubTransport(status: 401, body: "{}"), secrets, defaults)
        account.restore()
        #expect(account.role == .admin)
        await account.reload()
        #expect(account.account == nil)
        #expect(account.token == nil)
        #expect(defaults.data(forKey: "xr_identity.account") == nil)
    }

    @Test func suspendedMemberKeepsBlockedState() async throws {
        let secrets = MemorySecrets()
        secrets.values["session_token"] = "blocked"
        let body = #"{"account":{"id":"member","role":"client","access":"restricted","canNavigate":false}}"#
        let account = store(StubTransport(status: 403, body: body), secrets, freshDefaults())
        account.restore()
        await account.refresh()
        #expect(account.account?.isRestricted == true)
        #expect(!account.hasPlus)
        #expect(account.token == "blocked")
    }

    @Test func logoutForgetsTheSessionButNotThePhone() async {
        let secrets = MemorySecrets()
        let defaults = freshDefaults()
        let account = store(StubTransport(body: Self.accountBody), secrets, defaults)
        account.restore()
        await account.refresh()
        let device = account.deviceId
        account.logout()
        #expect(account.account == nil)
        #expect(secrets.values["session_token"] == nil)
        let relaunch = store(StubTransport(body: "{}"), secrets, defaults)
        relaunch.restore()
        #expect(relaunch.account == nil)
        #expect(relaunch.deviceId == device)
        #expect(await relaunch.updateProfile(username: "x") == AuthOutcome.failure("Non connecté"))
    }
}

@MainActor
struct LocalStoresTests {
    func place(_ id: String) -> Place {
        Place(id: id, name: "Lieu \(id)", subtitle: "Rennes", kind: .result, lat: 48.11, lon: -1.68)
    }

    @Test func preferencesSurviveARelaunch() {
        let defaults = freshDefaults()
        let preferences = PreferencesStore(defaults: defaults)
        #expect(preferences.settings.theme == .auto)
        #expect(preferences.alerts.voice)
        #expect(preferences.alerts.overspeed == .voice)
        // « Présence et position » activée d'office ; Protection pluie coupée.
        #expect(preferences.settings.presence)
        #expect(!preferences.settings.rainLock)
        preferences.updateAlerts {
            $0.voice = false
            $0.radarFixed = false
            $0.overspeed = .beep
            $0.guidanceVolume = 0.8
            $0.alertVolume = 0.3
        }
        preferences.updateSettings {
            $0.preferredFuel = .e85
            $0.avoidTolls = true
            $0.theme = .night
            $0.sharedTraffic = false
            $0.tripSuggestions = false
            $0.presence = false
            $0.rainLock = true
            $0.consumption = 5.5
        }
        let relaunch = PreferencesStore(defaults: defaults)
        #expect(!relaunch.alerts.voice)
        #expect(!relaunch.alerts.radarFixed)
        #expect(relaunch.alerts.overspeed == .beep)
        #expect(relaunch.settings.preferredFuel == .e85)
        #expect(relaunch.settings.avoidTolls)
        #expect(relaunch.settings.theme == .night)
        // Independent volumes, and the privacy switches (the traffic one under its first name).
        #expect(relaunch.alerts.guidanceVolume == 0.8 && relaunch.alerts.alertVolume == 0.3)
        #expect(!relaunch.settings.sharedTraffic && !relaunch.settings.tripSuggestions)
        #expect(relaunch.settings.drivingStats && !relaunch.settings.presence)
        #expect(relaunch.settings.rainLock)
        #expect(relaunch.settings.consumption == 5.5)
        defaults.set(99.0, forKey: "xr_prefs.consumption")
        #expect(PreferencesStore(defaults: defaults).settings.consumption == AppSettings.defaultConsumption)
        defaults.set(1.0, forKey: "xr_prefs.consumption")
        #expect(PreferencesStore(defaults: defaults).settings.consumption == 1.0)
        #expect(defaults.object(forKey: "xr_prefs.shareSlowdowns") as? Bool == false)
        defaults.set("Neon", forKey: "xr_prefs.theme")
        defaults.set("Neon", forKey: "xr_prefs.overspeed")
        #expect(PreferencesStore(defaults: defaults).settings.theme == .auto)
        #expect(PreferencesStore(defaults: defaults).alerts.overspeed == .voice)
    }

    @Test func presenceTurnedOnOnceForEarlierInstalls() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: "xr_prefs.presence")
        #expect(PreferencesStore(defaults: defaults).settings.presence)
        PreferencesStore(defaults: defaults).updateSettings { $0.presence = false }
        #expect(!PreferencesStore(defaults: defaults).settings.presence)
    }

    @Test func mopedVehiclesCapAt45() {
        #expect(VehicleType.scooter50.moped && VehicleType.licenseFree.moped)
        #expect(VehicleType.scooter50.speedCapKmh == 45)
        #expect(VehicleType.car.speedCapKmh == nil && !VehicleType.truck.moped)
        let defaults = freshDefaults()
        PreferencesStore(defaults: defaults).setVehicleType(.licenseFree)
        #expect(PreferencesStore(defaults: defaults).vehicleType == .licenseFree)
    }

    @Test func themeFromTheBasemapOfEarlierBuilds() {
        let defaults = freshDefaults()
        defaults.set("light", forKey: "xr_prefs.themeMode")
        defaults.set("dark", forKey: "xr_prefs.mapStyle")
        let preferences = PreferencesStore(defaults: defaults)
        #expect(preferences.settings.theme == .night)
        preferences.updateSettings { $0.avoidTolls = true }
        #expect(defaults.string(forKey: "xr_prefs.theme") == "night")
        #expect(defaults.object(forKey: "xr_prefs.mapStyle") == nil)
        #expect(defaults.object(forKey: "xr_prefs.themeMode") == nil)
        defaults.set("bright", forKey: "xr_prefs.mapStyle")
        defaults.removeObject(forKey: "xr_prefs.theme")
        #expect(PreferencesStore(defaults: defaults).settings.theme == .day)
    }

    @Test func alertSwitchesPerCategory() {
        let defaults = freshDefaults()
        // An earlier build's grouped switches.
        defaults.set(false, forKey: "xr_prefs.hazards")
        defaults.set(false, forKey: "xr_prefs.cameras")
        let migrated = PreferencesStore(defaults: defaults)
        #expect(!migrated.settings.fuelCashOnly)
        #expect(!migrated.alerts.shows(.accident))
        #expect(!migrated.alerts.shows(.camera))
        #expect(migrated.alerts.shows(.radarMobile))
        #expect(migrated.alerts.shows(.voitureRadar))
        migrated.updateAlerts { $0.toggle(.accident) }
        migrated.updateSettings {
            $0.fuelNearestOnly = true
            $0.fuelCashOnly = true
        }
        let relaunch = PreferencesStore(defaults: defaults)
        #expect(relaunch.alerts.shows(.accident))
        #expect(!relaunch.alerts.shows(.roadworks))
        #expect(relaunch.settings.fuelNearestOnly)
        #expect(relaunch.settings.fuelCashOnly)
    }

    @Test func tripsGoWithTheAccount() {
        let defaults = freshDefaults()
        let history = TripHistoryStore(defaults: defaults)
        history.add(TripRecord(id: "t", startedAt: 1, fromLabel: "A", toLabel: "B", distanceMeters: 1000, durationSeconds: 60, alertsCount: 0, topSpeedKmh: 50))
        history.removeAll()
        #expect(history.trips.isEmpty)
        #expect(TripHistoryStore(defaults: defaults).trips.isEmpty)
    }

    @Test func savedPlacesAndFavorites() {
        let defaults = freshDefaults()
        let saved = SavedPlacesStore(defaults: defaults)
        saved.setWork(place("w"))
        #expect(saved.work?.name == "Travail")
        #expect(saved.work?.kind == .work)
        for i in 0..<14 {
            saved.toggleFavorite(FavoriteTrip(to: place("f\(i)")))
        }
        #expect(saved.favorites.count == 12)
        #expect(saved.favorites.first?.to.id == "f13")
        saved.toggleFavorite(FavoriteTrip(to: place("f13")))
        #expect(!saved.isFavorite("f13"))
        #expect(FavoriteTrip(to: place("b"), from: place("a")).id == "a>b")

        let relaunch = SavedPlacesStore(defaults: defaults)
        #expect(relaunch.work?.subtitle == "Rennes")
        #expect(relaunch.favorites.count == 11)
        #expect(relaunch.favorites.first?.to.kind == .favorite)
        saved.setWork(nil)
        #expect(SavedPlacesStore(defaults: defaults).work == nil)
    }

    @Test func recentsKeepTheLastFifteen() {
        let defaults = freshDefaults()
        let recents = RecentsStore(defaults: defaults)
        for i in 0..<20 {
            recents.add(place("r\(i)"))
        }
        recents.add(place("r5"))
        #expect(recents.recents.count == 15)
        #expect(recents.recents.map(\.id).prefix(3) == ["r5", "r19", "r18"])
        recents.remove("r19")
        #expect(RecentsStore(defaults: defaults).recents.map(\.id).prefix(2) == ["r5", "r18"])
        #expect(recents.recents.allSatisfy { $0.kind == .recent })
    }

    @Test func tripHistoryNewestFirst() {
        let defaults = freshDefaults()
        let history = TripHistoryStore(defaults: defaults)
        history.add(TripRecord(id: "a", startedAt: 2_000, fromLabel: "", toLabel: "", distanceMeters: 1_500, durationSeconds: 60, alertsCount: 2, topSpeedKmh: 50))
        history.add(TripRecord(id: "b", startedAt: 1_000, fromLabel: "", toLabel: "", distanceMeters: 2_600, durationSeconds: 60, alertsCount: 1, topSpeedKmh: 90))
        #expect(history.trips.map(\.id) == ["a", "b"])
        #expect(history.stats == TripStats(trips: 2, kilometers: 4, alerts: 3))
        #expect(TripHistoryStore(defaults: defaults).trips.map(\.id) == ["a", "b"])
    }

    @Test func gpsSignal() {
        let state = LocationState()
        #expect(state.signal == .searching)
        state.update(LocationSample(latitude: 48, longitude: -1, speedMps: 10, bearingDeg: nil, accuracyM: 12, timeMs: 0))
        #expect(state.signal == .good)
        state.update(LocationSample(latitude: 48, longitude: -1, speedMps: 10, bearingDeg: nil, accuracyM: 45, timeMs: 1))
        #expect(state.signal == .weak)
        state.setLost()
        #expect(state.signal == .lost)
        state.reset()
        #expect(state.location == nil)
        #expect(state.signal == .searching)
    }

    @Test func clearingTheDestinationDropsTheRoute() {
        let trip = ActiveTripStore()
        trip.setDestination(place("d"))
        trip.setRoute(Route(points: [], distanceMeters: 0, durationSeconds: 0))
        trip.setDestination(nil)
        #expect(trip.route == nil)
    }

    @Test func stopsKeepOrderCapAndLeaveOneByOne() {
        let trip = ActiveTripStore()
        trip.setDestination(place("d"))
        trip.addStop(place("a"))
        trip.addStop(place("b"))
        trip.addStop(place("a"))
        trip.addStop(place("d"))
        #expect(trip.stops.map(\.id) == ["a", "b"])
        trip.setStops([place("b"), place("a")])
        trip.stopReached()
        #expect(trip.stops.map(\.id) == ["a"])
        for index in 0..<20 { trip.addStop(place("s\(index)")) }
        #expect(trip.stops.count == ActiveTripStore.maxStops)
        trip.setDestination(nil)
        #expect(trip.stops.isEmpty)
    }
}
