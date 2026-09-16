import Foundation
import Observation
import XRadarCore
import XRadarData

/// Which side of the road a report is on, from the driver's point of view.
enum ReportDirection {
    static let same = "same"
    static let opposite = "opposite"
}

/// What the report sheet collected: the category, which side of the road it is on, and the plate
/// of a radar car (optional: it only sharpens the probable zone).
struct ReportDraft: Equatable {
    let type: ReportType
    var direction = ReportDirection.same
    var plate: String? = nil
}

/// Everything the driving HUD renders in one frame, like the Android DriveUiState.
struct DriveState: Equatable {
    var speedKmh = 0
    var speedLimitKmh: Int?
    /// Where [speedLimitKmh] comes from: the road's own limit or a radar's VMA.
    var speedLimitSource: SpeedLimitSource?
    /// Non-nil only while navigating to a destination.
    var trip: TripInfo?
    /// The nearest live alert (voice and trip counting): the first of [alerts].
    var alert: RoadAlert?
    var gpsSignal: GpsSignal = .searching
    /// Every live alert, nearest first: the HUD stacks them all.
    var alerts: [RoadAlert] = []
    var location: LocationSample?
    /// What the map draws besides the driver.
    var map = DriveMapContent()
    /// The next maneuver, while navigating with steps.
    var guidance: GuidanceInstruction?
    /// A destination was picked but no route came back (network or provider down).
    var routeError = false

    var speedStatus: SpeedStatus? {
        SpeedStatus.of(speedKmh: speedKmh, limitKmh: speedLimitKmh)
    }

    var isSearchingGps: Bool {
        gpsSignal == .searching || gpsSignal == .lost
    }
}

/// Feeds the HUD from real data, like the Android DriveViewModel: the GPS (speed, position,
/// signal), the radars and reports around the driver or along the trip for the alerts and the
/// limit, the road's own limit, the route and its turn-by-turn voice once a destination is
/// chosen, the trip being recorded, and the app's presence for the backend's count. It lives as long as
/// the app and keeps running screen locked, where the voice still matters.
@MainActor
@Observable
final class DriveModel {
    private(set) var state = DriveState()
    /// Reports the driver voted on in this session: their vote buttons go away.
    private(set) var votedReports: Set<String> = []
    /// An action the backend refused for the account's access (trial over, a guest's limit of
    /// the day): the offers show, then it is acknowledged.
    private(set) var denial: AccessDenial?
    /// Keys of the alerts swiped off the HUD; each comes back after a while.
    private(set) var dismissedAlerts: Set<String> = []
    /// The music banner is open. HUD state only, never persisted.
    private(set) var musicOpen = false

    private let location: LocationState
    private let preferences: PreferencesStore
    private let account: AccountStore
    private let activeTrip: ActiveTripStore
    private let trips: TripHistoryStore
    private let speaker: GuidanceSpeaker
    private let sounds: AlertSoundPlayer
    private let music: MusicPlayer
    private let radarAPI: RadarAPI
    private let routingAPI: RoutingAPI
    private let reportsAPI: ReportsAPI
    private let speedLimitAPI: SpeedLimitAPI
    private let signAPI: SignAPI
    private let liveAPI: LiveAPI

    // Road data, as last loaded.
    @ObservationIgnored private var radars: [Radar] = []
    @ObservationIgnored private var reports: [UserReport] = []
    @ObservationIgnored private var zones: [RadarZone] = []
    @ObservationIgnored private var signs: [RoadSign] = []
    @ObservationIgnored private var guidance: GuidanceInstruction?
    /// The road's own limit where the driver is (nil = unknown).
    @ObservationIgnored private var roadLimit: Int?
    @ObservationIgnored private var routeError = false
    /// Reports the driver said are gone: never shown to them again, whatever the crowd says.
    @ObservationIgnored private var deniedReports: Set<String> = []

    // The active route: a version bumped at each new route, turn-by-turn, the corridor, limits along it.
    @ObservationIgnored private var routeVersion = 0
    @ObservationIgnored private var tracker = GuidanceTracker(route: nil)
    @ObservationIgnored private var corridor = RouteCorridor(route: [])
    @ObservationIgnored private var routeLimits: [RouteLimit] = []
    @ObservationIgnored private var routeLimitPath: RoutePath?
    /// True while the limit is read from the followed route (no polling then).
    @ObservationIgnored private var limitFromRoute = false
    @ObservationIgnored private var recalculating = false
    @ObservationIgnored private var lastRecalcAt = Date.distantPast

    // Radars: the route version they were loaded along (nil = the ring around the driver).
    @ObservationIgnored private var radarsRouteVersion: Int?
    @ObservationIgnored private var radarsOnRoute = false
    @ObservationIgnored private var ringLat = Double.nan
    @ObservationIgnored private var ringLon = Double.nan
    @ObservationIgnored private var ringRetryAt = Date.distantPast
    @ObservationIgnored private var radarsBusy = false
    @ObservationIgnored private var radarsAgain = false

    @ObservationIgnored private var lastFetchLat = Double.nan
    @ObservationIgnored private var lastFetchLon = Double.nan

    // The trip being recorded (saved when it ends).
    @ObservationIgnored private var tripActive = false
    @ObservationIgnored private var tripStartedAt = Date()
    @ObservationIgnored private var tripToLabel: String?
    @ObservationIgnored private var tripDistanceMeters = 0.0
    @ObservationIgnored private var tripTopSpeed = 0
    @ObservationIgnored private var tripAlerts = 0
    @ObservationIgnored private var lastTripLat = Double.nan
    @ObservationIgnored private var lastTripLon = Double.nan

    // Time and distance on the road with the app, trip or not, synced each minute.
    @ObservationIgnored private var driveLastLat = Double.nan
    @ObservationIgnored private var driveLastLon = Double.nan
    @ObservationIgnored private var driveLastAt = Date.distantPast
    @ObservationIgnored private var pendingSeconds = 0.0
    @ObservationIgnored private var pendingMeters = 0.0
    @ObservationIgnored private var lastFlush = Date()
    @ObservationIgnored private var flushing = false

    // Voice.
    @ObservationIgnored private var announcedAlerts: Set<String> = []
    @ObservationIgnored private var overspeeding = false
    @ObservationIgnored private var lastOverspeedAt = Date.distantPast
    @ObservationIgnored private var alertPresent = false

    // Alert sounds: alerts already announced by a sound, those past their laser burst, last beep.
    @ObservationIgnored private var soundedAlerts: Set<String> = []
    @ObservationIgnored private var burstAlerts: Set<String> = []
    @ObservationIgnored private var lastBeepAt = Date.distantPast

    @ObservationIgnored private var dismissTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var started = false

    init(services: AppServices) {
        location = services.location
        preferences = services.preferences
        account = services.account
        activeTrip = services.activeTrip
        trips = services.trips
        speaker = services.speaker
        sounds = services.alertSounds
        music = services.music
        radarAPI = RadarAPI(client: services.client)
        routingAPI = RoutingAPI(client: services.client)
        reportsAPI = ReportsAPI(client: services.client)
        speedLimitAPI = SpeedLimitAPI(client: services.client)
        signAPI = SignAPI(client: services.client)
        liveAPI = LiveAPI(client: services.client)
    }

    /// Starts the loops, once. They run for as long as the app does.
    func start() {
        guard !started else { return }
        started = true
        lastFlush = Date()
        Task { await followLocation() }
        Task { await followRoute() }
        Task { await followDestination() }
        Task { await followAvoidOptions() }
        Task { await followFilters() }
        Task { await refreshReportsLoop() }
        Task { await presenceLoop() }
        Task { await pollRoadLimitLoop() }
        Task { await proximityBeepLoop() }
    }

    // MARK: Driver actions

    /// Posts a report where the driver is, shown at once.
    func report(_ draft: ReportDraft) {
        guard let fix = location.location else { return }
        let newReport = NewReport(
            type: draft.type,
            lat: fix.latitude,
            lon: fix.longitude,
            plate: draft.plate,
            direction: draft.direction,
            bearingDeg: fix.bearingDeg
        )
        Task {
            let created: UserReport?
            do {
                created = try await reportsAPI.create(newReport, token: account.token, deviceId: account.deviceId)
            } catch let refused as AccessDenial {
                // Trial over, or today's reports used: the offers show instead.
                denial = refused
                await account.reload()
                return
            } catch {
                created = nil
            }
            // A radar car shows as a zone, which the reload brings. A report the backend merged
            // into one already there comes back as that one: replaced, not doubled.
            if let created, draft.type != .voitureRadar {
                reports = reports.filter { $0.id != created.id } + [created]
                recompute()
            }
            // A guest's count of the day moved on.
            if created != nil, account.account?.limits != nil {
                await account.reload()
            }
            await refreshReports(lat: fix.latitude, lon: fix.longitude)
        }
    }

    /// Admin moderation: deletes a report, then reloads.
    func deleteReport(_ id: String) {
        Task {
            _ = try? await reportsAPI.delete(id: id, token: account.token)
            reports = reports.filter { $0.id != id }
            recompute()
            if let fix = location.location {
                await refreshReports(lat: fix.latitude, lon: fix.longitude)
            }
        }
    }

    /// "Toujours là" (true) / "Plus là": one voice per person.
    func vote(_ id: String, confirm: Bool) {
        votedReports.insert(id)
        if !confirm {
            deniedReports.insert(id)
            reports = reports.filter { $0.id != id }
            recompute()
        }
        Task {
            _ = try? await reportsAPI.vote(id: id, confirm: confirm, token: account.token, deviceId: account.deviceId)
            if let fix = location.location {
                await refreshReports(lat: fix.latitude, lon: fix.longitude)
            }
        }
    }

    /// Proposes [newKmh] as the limit where the driver is. The HUD keeps its limit until the
    /// backend validates the change; when this proposal tips it, the new limit shows at once.
    func reportSpeedLimit(_ newKmh: Int) {
        guard let fix = location.location else { return }
        let shown = state
        Task {
            let proposal = NewSpeedLimitReport(
                lat: fix.latitude,
                lon: fix.longitude,
                bearingDeg: fix.bearingDeg,
                displayedKmh: shown.speedLimitKmh,
                displayedSource: shown.speedLimitSource,
                newKmh: newKmh
            )
            guard let change = try? await speedLimitAPI.report(proposal, token: account.token, deviceId: account.deviceId),
                  change.status == .validated,
                  let kmh = change.newKmh
            else { return }
            roadLimit = kmh
            recompute()
            if let route = activeTrip.route {
                await loadRouteSigns(route, version: routeVersion)
            }
        }
    }

    /// Hides one alert from the HUD for two minutes: display only, it stays live for the voice
    /// and the trip's count, and shows again afterwards if still ahead.
    func dismissAlert(_ key: String) {
        dismissedAlerts.insert(key)
        dismissTasks[key]?.cancel()
        dismissTasks[key] = Task {
            try? await Task.sleep(for: .seconds(Tuning.alertDismissSeconds))
            guard !Task.isCancelled else { return }
            dismissedAlerts.remove(key)
            dismissTasks[key] = nil
        }
    }

    /// The offers were shown for the last refusal.
    func acknowledgeDenial() {
        denial = nil
    }

    /// The music button: opens the banner (asking for access to Music the first time), or closes it.
    func toggleMusic() {
        musicOpen.toggle()
        if musicOpen { music.open() }
    }

    // MARK: Streams

    private func followLocation() async {
        for await fix in Observations({ self.location.location }) {
            onFix(fix)
        }
    }

    private func onFix(_ fix: LocationSample?) {
        if let fix {
            reloadReportsIfMoved(fix)
            countDriveTime(fix)
            recordTrip(fix)
            recalculateIfOffRoute(fix)
        }
        refreshRadarsSoon()
        followRouteLimit(fix)
        let update = tracker.update(sample: fix, voice: preferences.alerts.voice)
        guidance = update.instruction
        if let speech = update.speech {
            speaker.speak(speech)
        }
        recompute()
    }

    /// A new route (trip or recalculation): new turn-by-turn, corridor, radars and signs.
    private func followRoute() async {
        for await route in Observations({ self.activeTrip.route }) {
            routeVersion += 1
            tracker = GuidanceTracker(route: route)
            corridor = RouteCorridor(route: route?.points ?? [])
            if (route?.steps.count ?? 0) < 2 {
                guidance = nil
                speaker.stop()
            }
            refreshRadarsSoon()
            let version = routeVersion
            Task { await loadRouteSigns(route, version: version) }
            recompute()
        }
    }

    /// A destination chosen: start recording the trip and compute the route. Cleared: save it.
    private func followDestination() async {
        for await destination in Observations({ self.activeTrip.destination }) {
            guard let destination else {
                finalizeTrip()
                activeTrip.setRoute(nil)
                continue
            }
            startTrip(destination)
            routeError = false
            // A simulated departure wins over the GPS: that is the point of it.
            let simulated = activeTrip.start
            let here = location.location.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) }
            guard let from = simulated.map({ GeoPoint(lat: $0.lat, lon: $0.lon) }) ?? here else { continue }
            let to = GeoPoint(lat: destination.lat, lon: destination.lon)
            // Silent retries: a connection dropping for a few seconds should not kill the trip.
            var answer = await computeRoute(from: from, to: to)
            for delay in Tuning.routeRetrySeconds {
                guard case .failed = answer else { break }
                try? await Task.sleep(for: .seconds(delay))
                guard activeTrip.destination == destination else { break }
                let again = simulated != nil ? from : (location.location.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) } ?? from)
                answer = await computeRoute(from: again, to: to)
            }
            guard activeTrip.destination == destination else { continue }
            if case .denied(let refused) = answer {
                // Trial over, or today's trips used: no trip, the offers show.
                routeError = false
                activeTrip.clear()
                denial = refused
                recompute()
                Task { await account.reload() }
                continue
            }
            routeError = answer.route == nil
            activeTrip.setRoute(answer.route)
            recompute()
            // A guest's count of the day moved on.
            if answer.route != nil, account.account?.limits != nil {
                Task { await account.reload() }
            }
        }
    }

    /// Toll and motorway preferences: the live route is recomputed as soon as they change.
    private func followAvoidOptions() async {
        var previous: [String]?
        for await avoid in Observations({ self.avoidOptions() }) {
            let changed = previous != nil && previous != avoid
            previous = avoid
            guard changed, let destination = activeTrip.destination, let fix = location.location else { continue }
            let from = GeoPoint(lat: fix.latitude, lon: fix.longitude)
            if let route = await computeRoute(from: from, to: GeoPoint(lat: destination.lat, lon: destination.lon)).route {
                activeTrip.setRoute(route)
            }
        }
    }

    /// The alerts the driver asked for, and a trial running out, change what the HUD keeps.
    private func followFilters() async {
        for await _ in Observations({ (self.preferences.alerts, self.account.account?.isRestricted == true) }) {
            recompute()
        }
    }

    /// Reports are time-sensitive: reloaded on a short interval too.
    private func refreshReportsLoop() async {
        while true {
            if let fix = location.location {
                await refreshReports(lat: fix.latitude, lon: fix.longitude)
            }
            try? await Task.sleep(for: .seconds(Tuning.reportRefreshSeconds))
        }
    }

    /// Tells the backend the app is open, and whether a trip runs: counted there, shown to nobody,
    /// no position sent.
    private func presenceLoop() async {
        while true {
            if let token = account.token {
                _ = await liveAPI.presence(token: token, inTrip: activeTrip.destination != nil)
            }
            try? await Task.sleep(for: .seconds(Tuning.presenceSeconds))
        }
    }

    /// The limit under the car off the route, refreshed as the driver moves: the backend follows
    /// the road they are on (course, and the road id it gave last time).
    private func pollRoadLimitLoop() async {
        var lastLat = Double.nan
        var lastLon = Double.nan
        var lastHitAt = Date.distantPast
        var lastWayId: String?
        while true {
            if let fix = location.location, !limitFromRoute,
               lastLat.isNaN || Geo.haversine(lat1: lastLat, lon1: lastLon, lat2: fix.latitude, lon2: fix.longitude) > Tuning.limitMoveMeters {
                lastLat = fix.latitude
                lastLon = fix.longitude
                if let result = await signAPI.limit(lat: fix.latitude, lon: fix.longitude, bearingDeg: fix.bearingDeg, previousWayId: lastWayId) {
                    lastWayId = result.wayId ?? lastWayId
                    if let kmh = result.kmh {
                        roadLimit = kmh
                        lastHitAt = Date()
                    } else if Date().timeIntervalSince(lastHitAt) > Tuning.limitStaleSeconds {
                        // Nothing mapped here for a while: stop showing a stale sign.
                        roadLimit = nil
                    }
                    recompute()
                } else {
                    // No answer: the sign shown stays, and the next poll asks again.
                    lastLat = .nan
                }
            }
            try? await Task.sleep(for: .seconds(Tuning.limitPollSeconds))
        }
    }

    // MARK: Per fix

    private func reloadReportsIfMoved(_ fix: LocationSample) {
        guard lastFetchLat.isNaN
            || Geo.haversine(lat1: lastFetchLat, lon1: lastFetchLon, lat2: fix.latitude, lon2: fix.longitude) > Tuning.fetchMoveMeters
        else { return }
        lastFetchLat = fix.latitude
        lastFetchLon = fix.longitude
        Task { await refreshReports(lat: fix.latitude, lon: fix.longitude) }
    }

    private func countDriveTime(_ fix: LocationSample) {
        let now = Date()
        if !driveLastLat.isNaN && (fix.speedMps ?? 0) > Tuning.driveMinSpeedMps {
            let step = Geo.haversine(lat1: driveLastLat, lon1: driveLastLon, lat2: fix.latitude, lon2: fix.longitude)
            let seconds = now.timeIntervalSince(driveLastAt)
            if Tuning.stepMeters.contains(step) && (0...Tuning.driveMaxGapSeconds).contains(seconds) {
                pendingMeters += step
                pendingSeconds += seconds
            }
        }
        driveLastLat = fix.latitude
        driveLastLon = fix.longitude
        driveLastAt = now
        guard now.timeIntervalSince(lastFlush) >= Tuning.driveFlushSeconds, pendingSeconds >= 1, !flushing else { return }
        let seconds = Int(pendingSeconds)
        let meters = Int(pendingMeters)
        lastFlush = now
        flushing = true
        Task {
            if await account.postDrive(seconds: seconds, meters: meters) {
                pendingSeconds -= Double(seconds)
                pendingMeters -= Double(meters)
            }
            flushing = false
        }
    }

    /// Distance, top speed and arrival while a trip is active.
    private func recordTrip(_ fix: LocationSample) {
        guard tripActive else { return }
        if !lastTripLat.isNaN {
            let step = Geo.haversine(lat1: lastTripLat, lon1: lastTripLon, lat2: fix.latitude, lon2: fix.longitude)
            if Tuning.stepMeters.contains(step) { tripDistanceMeters += step }
        }
        lastTripLat = fix.latitude
        lastTripLon = fix.longitude
        tripTopSpeed = max(tripTopSpeed, Int(fix.speedKmh.rounded()))
        // Finished on its own at the destination.
        if let destination = activeTrip.destination,
           Geo.haversine(lat1: fix.latitude, lon1: fix.longitude, lat2: destination.lat, lon2: destination.lon) < Tuning.arriveMeters,
           tripDistanceMeters >= Double(Tuning.minTripMeters) {
            activeTrip.clear()
        }
    }

    /// The driver left the route: a new one from where they are.
    private func recalculateIfOffRoute(_ fix: LocationSample) {
        // A simulated trip is not being driven: never "correct" it.
        guard !recalculating, activeTrip.start == nil,
              let destination = activeTrip.destination,
              let route = activeTrip.route,
              let offBy = route.points.lazy.map({ Geo.haversine(lat1: fix.latitude, lon1: fix.longitude, lat2: $0.lat, lon2: $0.lon) }).min()
        else { return }
        let now = Date()
        guard offBy > Tuning.offRouteMeters, now.timeIntervalSince(lastRecalcAt) > Tuning.recalcCooldownSeconds else { return }
        lastRecalcAt = now
        recalculating = true
        Task {
            let fresh = await computeRoute(
                from: GeoPoint(lat: fix.latitude, lon: fix.longitude),
                to: GeoPoint(lat: destination.lat, lon: destination.lon)
            ).route
            recalculating = false
            if let fresh, activeTrip.destination == destination {
                activeTrip.setRoute(fresh)
            }
        }
    }

    /// On the route, the limit is read from its limit changes at the driver's progress: instant,
    /// and no request. Off it, the polling takes over.
    private func followRouteLimit(_ fix: LocationSample?) {
        guard let fix, let path = routeLimitPath, let first = routeLimits.first,
              let match = path.match(lat: fix.latitude, lon: fix.longitude),
              match.offRouteMeters <= Tuning.routeLimitMaxOffMeters
        else {
            limitFromRoute = false
            return
        }
        limitFromRoute = true
        roadLimit = (routeLimits.last { $0.along <= match.alongMeters } ?? first).kmh
    }

    // MARK: Loading

    /// A route, or why there is none: refused for the account's access, or simply not obtained.
    private enum RouteAnswer {
        case route(Route)
        case denied(AccessDenial)
        case failed

        var route: Route? {
            if case .route(let route) = self { return route }
            return nil
        }
    }

    private func computeRoute(from: GeoPoint, to: GeoPoint) async -> RouteAnswer {
        do {
            guard let route = try await routingAPI.route(from: from, to: to, avoid: avoidOptions(), token: account.token) else {
                return .failed
            }
            return .route(route)
        } catch let refused as AccessDenial {
            return .denied(refused)
        } catch {
            return .failed
        }
    }

    private func avoidOptions() -> [String] {
        var options: [String] = []
        if preferences.settings.avoidTolls { options.append("tolls") }
        if preferences.settings.avoidHighways { options.append("highways") }
        if preferences.settings.avoidTraffic { options.append("traffic") }
        return options
    }

    /// A failed reload keeps the reports already shown: a dropped connection is not an empty road.
    private func refreshReports(lat: Double, lon: Double) async {
        guard let near = try? await reportsAPI.near(lat: lat, lon: lon, radiusM: Tuning.reportsRadiusMeters) else { return }
        reports = near.reports.filter { !deniedReports.contains($0.id) }
        zones = near.zones
        recompute()
    }

    /// One radar refresh at a time; asked again while one runs, it runs once more after.
    private func refreshRadarsSoon() {
        guard !radarsBusy else {
            radarsAgain = true
            return
        }
        radarsBusy = true
        Task {
            repeat {
                radarsAgain = false
                await refreshRadars()
            } while radarsAgain
            radarsBusy = false
        }
    }

    /// The radars along the whole route while navigating (one request per route), a 22 km ring
    /// around the driver otherwise, reloaded every 5 km. A route the backend cannot answer for
    /// falls back to the ring; a failed request keeps the current list.
    private func refreshRadars() async {
        if let trip = activeTrip.route, trip.points.count >= 2 {
            let version = routeVersion
            if radarsRouteVersion != version {
                radarsRouteVersion = version
                let onRoute = try? await radarAPI.route(trip.points)
                radarsOnRoute = onRoute != nil
                if let onRoute {
                    radars = onRoute
                    recompute()
                } else {
                    ringLat = .nan
                }
            }
        } else {
            // Trip over: the ring around the driver comes back right away.
            if radarsRouteVersion != nil { ringLat = .nan }
            radarsRouteVersion = nil
            radarsOnRoute = false
        }
        guard !radarsOnRoute, let here = location.location else { return }
        let now = Date()
        guard now >= ringRetryAt,
              ringLat.isNaN || Geo.haversine(lat1: ringLat, lon1: ringLon, lat2: here.latitude, lon2: here.longitude) >= Tuning.radarRingRefreshMeters
        else { return }
        if let ring = try? await radarAPI.near(lat: here.latitude, lon: here.longitude, radiusM: Tuning.radarRingMeters) {
            radars = ring
            ringLat = here.latitude
            ringLon = here.longitude
            recompute()
        } else {
            ringRetryAt = now.addingTimeInterval(Tuning.radarRetrySeconds)
        }
    }

    /// The signs of the route (filtered by the backend for the way it runs) and its limit changes
    /// placed along it. Signs belong to the trip: none when simply driving around.
    private func loadRouteSigns(_ route: Route?, version: Int) async {
        let points = route?.points ?? []
        guard points.count >= 2 else {
            guard version == routeVersion else { return }
            signs = []
            routeLimits = []
            routeLimitPath = nil
            limitFromRoute = false
            recompute()
            return
        }
        // Without an answer the signs already shown stay, and the route asks again, less and less
        // often, until it gets them or is replaced.
        var answer = await signAPI.route(points)
        var delay = Tuning.signsRetrySeconds
        while answer == nil {
            try? await Task.sleep(for: .seconds(delay))
            guard version == routeVersion else { return }
            delay = min(delay * 2, Tuning.signsRetryMaxSeconds)
            answer = await signAPI.route(points)
        }
        let list = answer ?? []
        let placed = await Task.detached(priority: .userInitiated) {
            DriveModel.limitsAlong(points, signs: list)
        }.value
        guard version == routeVersion else { return }
        signs = list
        routeLimitPath = placed.path
        routeLimits = placed.limits
        recompute()
    }

    /// The limit changes among [signs], placed along the route, in order. Off the main actor:
    /// thousands of signs matched on a long route.
    nonisolated private static func limitsAlong(_ points: [GeoPoint], signs: [RoadSign]) -> PlacedLimits {
        let path = RoutePath(points: points)
        let limits = signs.compactMap { sign -> RouteLimit? in
            guard sign.type == .speedLimit, let kmh = sign.speed, let match = path.match(lat: sign.lat, lon: sign.lon) else { return nil }
            return RouteLimit(along: match.alongMeters, kmh: kmh)
        }
        let ordered = limits.enumerated()
            .sorted { ($0.element.along, $0.offset) < ($1.element.along, $1.offset) }
            .map(\.element)
        return PlacedLimits(path: path, limits: ordered)
    }

    // MARK: State

    /// Builds the HUD's frame from what is known now, then runs what follows it: the trip's
    /// alert count and the voice.
    private func recompute() {
        let sample = location.location
        let signal = location.signal
        let prefs = preferences.alerts
        let route = activeTrip.route
        // Trial over: the map stays, the radars and alerts do not.
        let restricted = account.account?.isRestricted == true
        var shownRadars = restricted ? [] : radars.filter { $0.isSpeedRadar ? prefs.radarFixed : prefs.shows(.camera) }
        // Everything the backend still serves is alive: the only filter left is the driver's choice.
        var shownReports = restricted ? [] : reports.filter { prefs.shows($0.type) }
        // While navigating, keep what is on the trip: near the route itself, or near the driver.
        if route != nil, let here = sample {
            shownRadars = shownRadars.filter { corridor.contains(lat: $0.lat, lon: $0.lon, driverLat: here.latitude, driverLon: here.longitude) }
            shownReports = shownReports.filter { corridor.contains(lat: $0.lat, lon: $0.lon, driverLat: here.latitude, driverLon: here.longitude) }
        }
        let speedKmh = signal == .searching || signal == .lost ? 0 : max(Int((sample?.speedKmh ?? 0).rounded()), 0)
        let radarsAhead = AlertsAhead.radars(shownRadars, sample: sample, speedKmh: speedKmh)
        let path = tracker.path
        // A traffic jam stays on the map but is no alert: the route can avoid it instead.
        let reportAlerts = AlertsAhead.reports(shownReports.filter { $0.type.raisesAlerts }, sample: sample, speedKmh: speedKmh) { report in
            // Only knowable while navigating; free driving assumes it is (better a spare alert
            // than a missed one).
            guard let path, let match = path.match(lat: report.lat, lon: report.lon) else { return true }
            return match.offRouteMeters <= Tuning.sameRoadMeters
        }
        let alerts = (radarsAhead.alerts + reportAlerts).enumerated()
            .sorted { ($0.element.distanceMeters, $0.offset) < ($1.element.distanceMeters, $1.offset) }
            .map(\.element)

        var limit = radarsAhead.limitKmh
        var source: SpeedLimitSource? = limit != nil ? .radar : nil
        // The road's own limit beats the radar VMA: it is true everywhere, all the time.
        if let roadLimit {
            limit = roadLimit
            source = .road
        }

        let next = DriveState(
            speedKmh: speedKmh,
            speedLimitKmh: limit,
            speedLimitSource: source,
            trip: route.map { TripInfo.of($0) },
            alert: alerts.first,
            gpsSignal: signal,
            alerts: alerts,
            location: sample,
            map: DriveMapContent(
                radars: shownRadars,
                reports: shownReports,
                zones: zones,
                signs: signs,
                routePoints: route?.points ?? []
            ),
            guidance: guidance,
            routeError: routeError
        )
        if next != state { state = next }

        // Distinct alert encounters during the trip.
        let present = next.alert != nil
        if present != alertPresent {
            alertPresent = present
            if present && tripActive { tripAlerts += 1 }
        }
        if prefs.sound {
            soundNewAlerts(next.alerts, vibrate: prefs.vibration)
        }
        guard prefs.voice else { return }
        announce(next.alert)
        announceOverspeed(speedKmh: next.speedKmh, limitKmh: next.speedLimitKmh)
    }

    /// A sound as each alert shows up: the detector's chirps for speed enforcement, a chime for a
    /// road hazard. One sound for several alerts appearing together.
    private func soundNewAlerts(_ alerts: [RoadAlert], vibrate: Bool) {
        if soundedAlerts.count > 300 {
            soundedAlerts.removeAll()
            burstAlerts.removeAll()
        }
        var fresh: [RoadAlert] = []
        for alert in alerts where soundedAlerts.insert(alert.key).inserted {
            fresh.append(alert)
        }
        guard !fresh.isEmpty else { return }
        sounds.play(fresh.contains { $0.type.isEnforcement } ? .detector : .hazard, vibrate: vibrate)
    }

    /// Radarbot's approach: beeps faster and faster toward the nearest speed enforcement ahead,
    /// then the laser burst at it. Quiet while the voice speaks or the car waits.
    private func proximityBeepLoop() async {
        while true {
            try? await Task.sleep(for: .milliseconds(100))
            let prefs = preferences.alerts
            guard prefs.sound, !speaker.isSpeaking,
                  let nearest = state.alert, nearest.type.isEnforcement,
                  state.speedKmh >= AlertBeeps.minSpeedKmh
            else { continue }
            if nearest.distanceMeters <= AlertBeeps.burstMeters {
                if burstAlerts.insert(nearest.key).inserted {
                    sounds.play(.laser, vibrate: prefs.vibration)
                }
                continue
            }
            let now = Date()
            guard let interval = AlertBeeps.interval(meters: nearest.distanceMeters),
                  now.timeIntervalSince(lastBeepAt) >= interval
            else { continue }
            lastBeepAt = now
            sounds.play(.beep, vibrate: prefs.vibration)
        }
    }

    /// An approaching radar or report, once around 500 m and once around 200 m.
    private func announce(_ alert: RoadAlert?) {
        guard let alert, let id = alert.id, let cue = AlertsAhead.announcement(for: alert) else { return }
        if announcedAlerts.count > 300 { announcedAlerts.removeAll() }
        if announcedAlerts.insert("\(id)@\(cue.band)").inserted {
            speaker.speak(cue.text)
        }
    }

    /// Once when clearly over the limit, then an occasional reminder while it lasts.
    private func announceOverspeed(speedKmh: Int, limitKmh: Int?) {
        guard let limitKmh, limitKmh > 0 else { return }
        guard speedKmh > limitKmh + Tuning.overspeedMargin else {
            overspeeding = false
            return
        }
        let now = Date()
        if overspeeding && now.timeIntervalSince(lastOverspeedAt) < Tuning.overspeedCooldownSeconds { return }
        overspeeding = true
        lastOverspeedAt = now
        speaker.speak("Vous dépassez la limite de \(limitKmh).")
    }

    // MARK: Trip

    private func startTrip(_ destination: Place) {
        tripToLabel = destination.name
        guard !tripActive else { return }
        tripActive = true
        tripStartedAt = Date()
        tripDistanceMeters = 0
        tripTopSpeed = 0
        tripAlerts = 0
        lastTripLat = .nan
        lastTripLon = .nan
    }

    /// Saves the finished trip if it is worth keeping, locally and on the server.
    private func finalizeTrip() {
        guard tripActive else { return }
        let duration = Int(Date().timeIntervalSince(tripStartedAt))
        let distance = Int(tripDistanceMeters.rounded())
        if distance >= Tuning.minTripMeters && duration >= Tuning.minTripSeconds {
            let record = TripRecord(
                id: UUID().uuidString.lowercased(),
                startedAt: Int(tripStartedAt.timeIntervalSince1970 * 1000),
                fromLabel: "Ma position",
                toLabel: tripToLabel ?? "Destination",
                distanceMeters: distance,
                durationSeconds: duration,
                alertsCount: tripAlerts,
                topSpeedKmh: tripTopSpeed
            )
            trips.add(record)
            // Statistics live on the server for everyone: they survive a reinstall.
            Task { _ = await account.postTrip(record) }
        }
        tripActive = false
        tripToLabel = nil
    }
}

/// A limit change along the route: where (metres along it) and what.
nonisolated private struct RouteLimit: Sendable {
    let along: Double
    let kmh: Int
}

nonisolated private struct PlacedLimits: Sendable {
    let path: RoutePath
    let limits: [RouteLimit]
}

private enum Tuning {
    /// Reports: all of France in one go, reloaded after a long drive and every 25 s.
    static let reportsRadiusMeters = 1_000_000
    static let fetchMoveMeters = 50_000.0
    static let reportRefreshSeconds = 25.0
    /// Radars outside a trip: a 22 km ring, reloaded every 5 km so 17 km ahead are always
    /// covered; a failed request is retried after 20 s.
    static let radarRingMeters = 22_000
    static let radarRingRefreshMeters = 5_000.0
    static let radarRetrySeconds = 20.0
    /// The app tells the backend it is open this often (the backend forgets it after 90 s).
    static let presenceSeconds = 30.0
    /// Route signs not loaded: asked again after 3 s, then less often, up to every 30 s.
    static let signsRetrySeconds = 3.0
    static let signsRetryMaxSeconds = 30.0
    // Trip recording.
    static let arriveMeters = 45.0
    static let minTripMeters = 500
    static let minTripSeconds = 60
    static let stepMeters: ClosedRange<Double> = 1...250
    // Drive-time accounting: moving above ~5 km/h, gaps over 10 s ignored, synced each minute.
    static let driveMinSpeedMps = 1.5
    static let driveMaxGapSeconds = 10.0
    static let driveFlushSeconds = 60.0
    static let offRouteMeters = 45.0
    static let recalcCooldownSeconds = 2.5
    /// A trip's first route: asked again after these pauses before giving up.
    static let routeRetrySeconds = [1.2, 3.0, 6.0]
    /// Off the route by more than this, a report is on another road.
    static let sameRoadMeters = 60.0
    // Road limit.
    static let limitMoveMeters = 40.0
    /// Farther than this from the route, its limits are not the driver's.
    static let routeLimitMaxOffMeters = 30.0
    static let limitPollSeconds = 2.5
    static let limitStaleSeconds = 25.0
    // Voice.
    static let overspeedMargin = 5
    static let overspeedCooldownSeconds = 60.0
    /// An alert swiped off the HUD stays hidden this long.
    static let alertDismissSeconds = 120.0
}
