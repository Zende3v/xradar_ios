import Foundation
import Observation
import EonaCore
import EonaData

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
    /// "Oui" to "Ralentissement du trafic ?".
    var prompted = false
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

/// A faster way around the traffic was just taken: the banner saying how much time it saves,
/// or that it goes around a closed road.
struct FasterRouteNotice: Equatable {
    let id = UUID()
    let gainMinutes: Int
    var closedRoad = false
}

/// The trip just reached its destination: what the arrival card shows, a few seconds, before
/// the HUD goes back to simply driving.
struct TripArrival: Equatable {
    let id = UUID()
    let toLabel: String
    let distanceMeters: Int
    let durationSeconds: Int
    let alertsCount: Int
}

/// "Ralentissement du trafic ?", asked a few seconds about a slowdown nobody knows of yet.
struct SlowdownPrompt: Equatable {
    let id = UUID()
    let slowdown: Slowdown
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
    /// Shown a few seconds after a switch to a faster route.
    private(set) var fasterNotice: FasterRouteNotice?
    /// Asked a few seconds after a slowdown the backend did not know of.
    private(set) var slowdownPrompt: SlowdownPrompt?
    /// Shown a few seconds once the destination is reached.
    private(set) var arrival: TripArrival?
    /// "Partager mon trajet": the live link, nil when nothing is shared.
    private(set) var tripShare: TripShare?
    /// True while the link is being opened, so the button says something.
    private(set) var openingShare = false
    @ObservationIgnored private var lastShareUpdateAt = Date.distantPast
    /// True when the trip ended at its destination, as opposed to being stopped on the way.
    private var arrived = false

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
    private let shareAPI: TripShareAPI
    private let trafficAPI: TrafficAPI

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
    /// TomTom's traffic on the route being followed, measured along it; nil until known.
    @ObservationIgnored private var traffic: RouteTraffic?
    /// The route followed, for the driver's progress along it.
    @ObservationIgnored private var routePath: RoutePath?
    /// True while the limit is read from the followed route (no polling then).
    @ObservationIgnored private var limitFromRoute = false
    @ObservationIgnored private var recalculating = false
    @ObservationIgnored private var lastRecalcAt = Date.distantPast
    /// Where the last recalculation was asked from: the next one waits for real driving.
    @ObservationIgnored private var recalcFrom: GeoPoint?
    @ObservationIgnored private var recalcWait = Tuning.recalcCooldownSeconds
    /// True once the driver has actually been on the route: before that the trip has not started.
    @ObservationIgnored private var joinedRoute = false
    /// When the current route started waiting to be joined (nil: none waiting).
    @ObservationIgnored private var waitingSince: Date?
    /// "Éviter les bouchons": a faster-route check running, the last one asked, and the trip's
    /// last switch for traffic, for the destination they were about (the same place chosen
    /// again keeps them).
    @ObservationIgnored private var checkingFaster = false
    @ObservationIgnored private var lastFasterCheckAt = Date.distantPast
    @ObservationIgnored private var lastTrafficRerouteAt: Date?
    @ObservationIgnored private var fasterDestinationId: String?

    // "Partager les ralentissements": the detector, and where the driver said "Non" lately.
    @ObservationIgnored private var slowdownDetector = SlowdownDetector()
    @ObservationIgnored private var declinedSlowdowns: [(lat: Double, lon: Double, until: Date)] = []

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

    /// The trip being recorded (saved when it ends).
    @ObservationIgnored private var trip: TripRecorder?

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
        shareAPI = TripShareAPI(client: services.client)
        trafficAPI = TrafficAPI(client: services.client)
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
        Task { await trafficLoop() }
        Task { await followTrafficAvoidance() }
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
            bearingDeg: fix.bearingDeg,
            prompted: draft.prompted
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
            Task { await pushShare() }
        }
        refreshRadarsSoon()
        followRouteLimit(fix)
        let update = tracker.update(sample: fix, voice: preferences.alerts.voice)
        guidance = update.instruction
        if let speech = update.speech {
            speaker.speak(speech, volume: preferences.alerts.guidanceVolume)
        }
        recompute()
        if let fix { detectSlowdown(fix) }
    }

    /// A new route (trip or recalculation): new turn-by-turn, corridor, radars and signs.
    private func followRoute() async {
        for await route in Observations({ self.activeTrip.route }) {
            // Another route: it has to be joined in its turn (a recalculation can start on a road
            // the driver is not on yet).
            joinedRoute = false
            waitingSince = nil
            routeVersion += 1
            tracker = GuidanceTracker(route: route)
            corridor = RouteCorridor(route: route?.points ?? [])
            routePath = route.map { RoutePath(points: $0.points) }
            if (route?.steps.count ?? 0) < 2 {
                guidance = nil
                speaker.stop()
            }
            refreshRadarsSoon()
            let version = routeVersion
            Task { await loadRouteSigns(route, version: version) }
            // Another route, another geometry: its traffic is asked for at once.
            traffic = nil
            Task { await refreshTraffic(version: version) }
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
            if destination.id != fasterDestinationId {
                fasterDestinationId = destination.id
                lastTrafficRerouteAt = nil
                lastFasterCheckAt = .distantPast
            }
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
            // The trip's estimate, for "temps réel vs temps prévu".
            if let route = answer.route { trip?.plan(route) }
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

    /// The traffic on the route being followed, every two minutes while a trip runs (a new route
    /// asks at once). Nothing is fetched without a trip.
    private func trafficLoop() async {
        while true {
            try? await Task.sleep(for: .seconds(Tuning.trafficRefreshSeconds))
            await refreshTraffic(version: routeVersion)
        }
    }

    /// A failed request keeps the colours shown; an answer for a route since replaced is dropped.
    /// The driver's progress goes along: the backend says whether a faster route may exist ahead.
    private func refreshTraffic(version: Int) async {
        guard let route = activeTrip.route, route.points.count >= 2 else { return }
        let ahead = progress()?.alongMeters
        guard let fresh = await trafficAPI.route(route.points, aheadMeters: ahead, token: account.token), version == routeVersion else { return }
        if fresh != traffic {
            traffic = fresh
            recompute()
        }
        await considerFasterRoute(fresh, version: version)
    }

    /// "Éviter les bouchons" turned on during a trip: the traffic already known is looked at now.
    private func followTrafficAvoidance() async {
        for await on in Observations({ self.preferences.settings.avoidTraffic }) {
            guard on, let traffic else { continue }
            await considerFasterRoute(traffic, version: routeVersion)
        }
    }

    /// Where the driver is along the route followed; nil off it (or on a simulated trip).
    private func progress() -> RoutePath.Match? {
        guard activeTrip.start == nil, let fix = location.location,
              let match = routePath?.match(lat: fix.latitude, lon: fix.longitude),
              match.offRouteMeters <= Tuning.offRouteMeters
        else { return nil }
        return match
    }

    /// "Éviter les bouchons": when the backend says the traffic ahead (TomTom's and the drivers'
    /// jams) may be worth going around, it looks for a faster way, and the trip takes it when it
    /// saves enough time (the backend's thresholds, stricter a while after a switch) or goes
    /// around a closed road. Never a detour for a jam alone, never within a few minutes of the
    /// last switch, never for a simulated trip; asked again every few minutes at most (each
    /// check costs several TomTom and ORS requests).
    private func considerFasterRoute(_ traffic: RouteTraffic, version: Int) async {
        guard traffic.worthChecking, preferences.settings.avoidTraffic, !checkingFaster,
              let destination = activeTrip.destination, let path = routePath
        else { return }
        if let last = lastTrafficRerouteAt, Date().timeIntervalSince(last) < Tuning.fasterCooldownSeconds { return }
        guard Date().timeIntervalSince(lastFasterCheckAt) >= Tuning.fasterRecheckSeconds, let match = progress() else { return }

        checkingFaster = true
        lastFasterCheckAt = Date()
        defer { checkingFaster = false }
        let since = lastTrafficRerouteAt.map { Int(Date().timeIntervalSince($0)) }
        guard let faster = await routingAPI.faster(
                  path.trimmed(from: match.alongMeters), avoid: avoidOptions(), sinceRerouteSeconds: since, token: account.token
              ),
              version == routeVersion, activeTrip.destination == destination
        else { return }
        lastTrafficRerouteAt = Date()
        activeTrip.setRoute(faster.route)
        announceFaster(FasterRouteNotice(gainMinutes: max(1, Int((Double(faster.gainSeconds) / 60).rounded())), closedRoad: faster.closed))
    }

    /// The switch, said (to the end: the new route's first instruction waits) and shown a moment.
    private func announceFaster(_ notice: FasterRouteNotice) {
        fasterNotice = notice
        if preferences.alerts.voice {
            let saved = notice.gainMinutes > 1 ? "\(notice.gainMinutes) minutes gagnées" : "1 minute gagnée"
            speaker.speak(
                notice.closedRoad ? "Route fermée devant : nouvel itinéraire." : "Itinéraire plus rapide trouvé : \(saved).",
                volume: preferences.alerts.guidanceVolume,
                whole: true
            )
        }
        Task {
            try? await Task.sleep(for: .seconds(Tuning.fasterNoticeSeconds))
            if fasterNotice == notice { fasterNotice = nil }
        }
    }

    // MARK: Slowdowns

    /// "Partager les ralentissements": a crawl on a fast road (SlowdownDetector) goes to the
    /// backend, anonymously; when no jam is known there yet, the driver is asked
    /// "Ralentissement du trafic ?" for a few seconds. Nothing while the trip starts or ends.
    private func detectSlowdown(_ fix: LocationSample) {
        guard preferences.settings.sharedTraffic, account.token != nil else { return }
        var paused = false
        if let destination = activeTrip.destination {
            let driven = trip?.distanceMeters ?? 0
            let left = Geo.haversine(lat1: fix.latitude, lon1: fix.longitude, lat2: destination.lat, lon2: destination.lon)
            paused = driven < Tuning.slowdownTripStartMeters || left < Tuning.slowdownTripEndMeters
        }
        guard let slowdown = slowdownDetector.update(
            sample: fix,
            speedKmh: state.speedKmh,
            limitKmh: state.speedLimitKmh,
            limitFromRoad: state.speedLimitSource == .road,
            paused: paused
        ) else { return }
        Task { await shareSlowdown(slowdown) }
    }

    private func shareSlowdown(_ slowdown: Slowdown) async {
        let known = await trafficAPI.probe(slowdown, token: account.token)
        let now = Date()
        declinedSlowdowns.removeAll { $0.until <= now }
        // Known to the backend, to TomTom here, or a "Bouchon" close by: nothing to ask. A
        // blocked account is not asked either (it could not report).
        guard known == false, slowdownPrompt == nil, account.account?.isRestricted != true,
              !trafficKnownHere(slowdown),
              !declinedSlowdowns.contains(where: { Geo.haversine(lat1: $0.lat, lon1: $0.lon, lat2: slowdown.lat, lon2: slowdown.lon) < Tuning.slowdownDeclineMeters })
        else { return }
        let prompt = SlowdownPrompt(slowdown: slowdown)
        slowdownPrompt = prompt
        Task {
            try? await Task.sleep(for: .seconds(Tuning.slowdownPromptSeconds))
            if slowdownPrompt == prompt { slowdownPrompt = nil }
        }
    }

    /// Whether the trip's traffic already slows the road where the driver is, or a "Bouchon"
    /// report lies close by.
    private func trafficKnownHere(_ slowdown: Slowdown) -> Bool {
        if let traffic, let path = routePath, let match = progress(), traffic.slowed(at: match.alongMeters, routeMeters: path.totalMeters) {
            return true
        }
        return reports.contains {
            $0.type == .trafficJam && Geo.haversine(lat1: $0.lat, lon1: $0.lon, lat2: slowdown.lat, lon2: slowdown.lon) < Tuning.slowdownKnownMeters
        }
    }

    /// "Oui": a "Bouchon" report there (a guest's quota spared); "Non": the probe is taken back
    /// and the driver is not asked again around there for a while.
    func answerSlowdown(_ yes: Bool) {
        guard let prompt = slowdownPrompt else { return }
        slowdownPrompt = nil
        if yes {
            report(ReportDraft(type: .trafficJam, prompted: true))
        } else {
            declinedSlowdowns.append((lat: prompt.slowdown.lat, lon: prompt.slowdown.lon, until: Date().addingTimeInterval(Tuning.slowdownDeclineSeconds)))
            Task { await trafficAPI.dismissProbe(token: account.token) }
        }
    }

    /// Tells the backend the app is open, and whether a trip runs. The position goes with it only
    /// with "Présence et position", the time spent only with "Temps d'utilisation": both off,
    /// nothing is sent at all.
    private func presenceLoop() async {
        while true {
            let privacy = preferences.settings
            if let token = account.token, privacy.presence || privacy.usageTime {
                let fix = privacy.presence ? location.location : nil
                _ = await liveAPI.presence(
                    token: token,
                    inTrip: activeTrip.destination != nil,
                    position: fix.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) },
                    speedKmh: fix.flatMap { $0.speedMps }.map { Int(max(0, ($0 * 3.6).rounded())) },
                    countTime: privacy.usageTime
                )
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
        // "Statistiques de conduite" off: nothing counted, nothing sent.
        guard preferences.settings.drivingStats else {
            driveLastLat = .nan
            pendingSeconds = 0
            pendingMeters = 0
            return
        }
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

    /// Distance, speed and stops while a trip is active, and its arrival.
    private func recordTrip(_ fix: LocationSample) {
        guard trip != nil else { return }
        trip?.add(fix)
        // Finished on its own at the destination.
        if let destination = activeTrip.destination, let driven = trip?.distanceMeters,
           Geo.haversine(lat1: fix.latitude, lon1: fix.longitude, lat2: destination.lat, lon2: destination.lon) < Tuning.arriveMeters,
           driven >= TripRecorder.minMeters {
            arrived = true
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
        // On the route: the trip has really started, and a detour may be corrected later.
        if offBy <= Tuning.offRouteMeters {
            joinedRoute = true
            recalcWait = Tuning.recalcCooldownSeconds
            return
        }
        let speed = fix.speedMps ?? 0
        // Not joined yet: the driver is simply not there — in a building, a car park, a lane the
        // routing does not know. Nothing to correct until they really drive, and a route nobody
        // ever joins is dropped instead of waiting forever.
        if !joinedRoute {
            let since = waitingSince ?? now
            waitingSince = since
            if speed < Tuning.driveMinSpeedMps, now.timeIntervalSince(since) > Tuning.tripAbandonSeconds {
                activeTrip.clear()
                return
            }
        }
        guard speed >= (joinedRoute ? Tuning.driveMinSpeedMps : Tuning.recalcStartSpeedMps) else { return }
        // Standing still, or barely moved since the last one: asking again would give the same
        // answer. Only real driving earns a new route.
        let moved = recalcFrom.map {
            Geo.haversine(lat1: $0.lat, lon1: $0.lon, lat2: fix.latitude, lon2: fix.longitude)
        } ?? .greatestFiniteMagnitude
        guard moved >= (joinedRoute ? Tuning.recalcMinMoveMeters : Tuning.recalcStartMoveMeters),
              now.timeIntervalSince(lastRecalcAt) > recalcWait
        else { return }
        lastRecalcAt = now
        recalcFrom = GeoPoint(lat: fix.latitude, lon: fix.longitude)
        recalculating = true
        Task {
            let fresh = await computeRoute(
                from: GeoPoint(lat: fix.latitude, lon: fix.longitude),
                to: GeoPoint(lat: destination.lat, lon: destination.lon)
            ).route
            recalculating = false
            if let fresh {
                recalcWait = Tuning.recalcCooldownSeconds
                if activeTrip.destination == destination { activeTrip.setRoute(fresh) }
            } else {
                // No answer: wait longer each time instead of asking again straight away.
                recalcWait = min(recalcWait * 2, Tuning.recalcWaitMaxSeconds)
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
        // "Éviter les bouchons" no longer avoids every reported jam: the faster-route check
        // weighs the time saved instead (considerFasterRoute).
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
        var shownZones = zones
        if let here = sample {
            if route != nil {
                // While navigating, keep what is on the trip: near the route itself, or near the driver.
                shownRadars = shownRadars.filter { corridor.contains(lat: $0.lat, lon: $0.lon, driverLat: here.latitude, driverLon: here.longitude) }
                shownReports = shownReports.filter { corridor.contains(lat: $0.lat, lon: $0.lon, driverLat: here.latitude, driverLon: here.longitude) }
                shownZones = shownZones.filter { corridor.contains(lat: $0.lat, lon: $0.lon, driverLat: here.latitude, driverLon: here.longitude) }
            } else {
                // Free driving: the reports around the driver only, the same ring as the fixed
                // radars. Everyone's alike, admins' included: their trust changes nothing here.
                let ring = Double(Tuning.radarRingMeters)
                shownReports = shownReports.filter { Geo.haversine(lat1: here.latitude, lon1: here.longitude, lat2: $0.lat, lon2: $0.lon) <= ring }
                shownZones = shownZones.filter { Geo.haversine(lat1: here.latitude, lon1: here.longitude, lat2: $0.lat, lon2: $0.lon) <= ring + $0.radiusMeters }
            }
        } else if route == nil {
            // No position yet: nothing to be around.
            shownReports = []
            shownZones = []
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
                zones: shownZones,
                signs: signs,
                routePoints: route?.points ?? [],
                traffic: route == nil ? nil : traffic
            ),
            guidance: guidance,
            routeError: routeError
        )
        if next != state { state = next }

        // The alerts the trip reaches, each once, for its history.
        trip?.meet(next.alerts)
        if prefs.sound {
            soundNewAlerts(next.alerts, vibrate: prefs.vibration)
        }
        if prefs.voice {
            announce(next.alert)
        }
        warnOverspeed(speedKmh: next.speedKmh, limitKmh: next.speedLimitKmh, prefs: prefs)
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
        sounds.play(fresh.contains { $0.type.isEnforcement } ? .detector : .hazard, vibrate: vibrate, volume: preferences.alerts.alertVolume)
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
                    sounds.play(.laser, vibrate: prefs.vibration, volume: prefs.alertVolume)
                }
                continue
            }
            let now = Date()
            guard let interval = AlertBeeps.interval(meters: nearest.distanceMeters),
                  now.timeIntervalSince(lastBeepAt) >= interval
            else { continue }
            lastBeepAt = now
            sounds.play(.beep, vibrate: prefs.vibration, volume: prefs.alertVolume)
        }
    }

    /// An approaching radar or report, once around 500 m and once around 200 m.
    private func announce(_ alert: RoadAlert?) {
        guard let alert, let id = alert.id, let cue = AlertsAhead.announcement(for: alert) else { return }
        if announcedAlerts.count > 300 { announcedAlerts.removeAll() }
        if announcedAlerts.insert("\(id)@\(cue.band)").inserted {
            speaker.speak(cue.text, volume: preferences.alerts.alertVolume)
        }
    }

    /// Once when clearly over the limit, then an occasional reminder while it lasts: spoken or
    /// beeped, as "Dépassement limitation" says, and only while the voice or the sound is on.
    private func warnOverspeed(speedKmh: Int, limitKmh: Int?, prefs: AlertPreferences) {
        guard let limitKmh, limitKmh > 0 else { return }
        guard speedKmh > limitKmh + Tuning.overspeedMargin else {
            overspeeding = false
            return
        }
        let now = Date()
        if overspeeding && now.timeIntervalSince(lastOverspeedAt) < Tuning.overspeedCooldownSeconds { return }
        overspeeding = true
        lastOverspeedAt = now
        switch prefs.overspeed {
        case .voice where prefs.voice:
            speaker.speak("Vous dépassez la limite de \(limitKmh).", volume: prefs.alertVolume)
        case .beep where prefs.sound:
            sounds.play(.overspeed, vibrate: prefs.vibration, volume: prefs.alertVolume)
        default:
            break
        }
    }

    // MARK: Trip

    /// A new destination starts a trip, or redirects the one running (a new estimate follows).
    private func startTrip(_ destination: Place) {
        if trip == nil {
            trip = TripRecorder(toLabel: destination.name)
        } else {
            trip?.retarget(destination.name)
        }
    }

    /// Saves the finished trip if it is worth keeping, locally and on the server.
    private func finalizeTrip() {
        guard let finished = trip else { return }
        trip = nil
        // Arrived, not stopped on the way: the HUD says so before going back to simply driving.
        if arrived {
            arrived = false
            showArrival(finished)
        }
        // Whoever follows the trip sees the arrival, then the link goes out.
        if tripShare != nil {
            Task { await pushShare(arrived: true) }
        }
        // "Statistiques de conduite" off: the trip only served the guidance (its arrival).
        guard preferences.settings.drivingStats, let record = finished.record(id: UUID().uuidString.lowercased()) else { return }
        trips.add(record)
        // Statistics live on the server for everyone: they survive a reinstall.
        Task { _ = await account.postTrip(record) }
    }

    /// The destination is reached: the card, with the trip's figures, for a few seconds.
    private func showArrival(_ finished: TripRecorder) {
        let reached = TripArrival(
            toLabel: finished.toLabel,
            distanceMeters: Int(finished.distanceMeters.rounded()),
            durationSeconds: Int(Date().timeIntervalSince(finished.startedAt)),
            alertsCount: finished.alertsMet
        )
        arrival = reached
        Task {
            try? await Task.sleep(for: .seconds(Tuning.arrivalSeconds))
            if arrival == reached { arrival = nil }
        }
    }

    /// The driver closed the arrival card.
    func dismissArrival() {
        arrival = nil
    }

    // ---- "Partager mon trajet" ------------------------------------------------------

    /// Opens a link on the trip being driven, and hands it back for the share sheet.
    @discardableResult
    func startSharing() async -> TripShare? {
        guard let token = account.token, let route = activeTrip.route else { return nil }
        openingShare = true
        let share = await shareAPI.open(
            toLabel: activeTrip.destination?.name,
            destination: activeTrip.destination.map { GeoPoint(lat: $0.lat, lon: $0.lon) },
            route: route.points,
            token: token
        )
        openingShare = false
        tripShare = share
        if share != nil { await pushShare(force: true) }
        return share
    }

    /// Stops sharing: the link dies at once.
    func stopSharing() async {
        guard tripShare != nil else { return }
        _ = await shareAPI.close(token: account.token)
        tripShare = nil
    }

    /// Where the driver is and what is left of the trip, sent while someone may be watching.
    private func pushShare(force: Bool = false, arrived: Bool = false) async {
        guard tripShare != nil, let token = account.token else { return }
        let now = Date()
        guard force || arrived || now.timeIntervalSince(lastShareUpdateAt) >= Tuning.shareUpdateSeconds else { return }
        lastShareUpdateAt = now
        let fix = location.location
        var remaining: Int?
        var eta: Int?
        if let route = activeTrip.route, let path = routePath, let match = progress() {
            let left = max(0, path.totalMeters - match.alongMeters)
            remaining = Int(left.rounded())
            let share = path.totalMeters > 0 ? left / path.totalMeters : 0
            eta = Int((Double(route.durationSeconds) * share).rounded())
        }
        let updated = await shareAPI.update(
            position: fix.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) },
            bearing: fix?.bearingDeg,
            remainingMeters: remaining,
            etaSeconds: eta,
            arrived: arrived,
            token: token
        )
        // Refused (link over, trip finished elsewhere): the button goes back to "partager".
        tripShare = updated ?? (arrived ? nil : tripShare)
        if arrived { tripShare = nil }
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
    /// The route's traffic is asked for again this often during a trip.
    static let trafficRefreshSeconds = 120.0
    /// A faster route is looked for when the backend says so, not within this long of the last
    /// switch, and again this long after a check at the earliest.
    static let fasterCooldownSeconds = 300.0
    static let fasterRecheckSeconds = 300.0
    /// The "Itinéraire plus rapide" banner stays this long.
    static let fasterNoticeSeconds = 8.0
    // "Ralentissement du trafic ?": asked this long; nothing in a trip's first or last metres;
    // not again this close to a "Non" for this long; a "Bouchon" this close is already known.
    static let slowdownPromptSeconds = 10.0
    /// How long the arrival card stays before going on its own.
    static let arrivalSeconds = 15.0
    static let slowdownTripStartMeters = 300.0
    static let slowdownTripEndMeters = 500.0
    static let slowdownDeclineSeconds = 900.0
    static let slowdownDeclineMeters = 3_000.0
    static let slowdownKnownMeters = 1_000.0
    /// The app tells the backend it is open this often (the backend forgets it after 90 s).
    static let presenceSeconds = 30.0
    /// "Partager mon trajet": the follower sees the driver move at this pace.
    static let shareUpdateSeconds = 10.0
    /// Route signs not loaded: asked again after 3 s, then less often, up to every 30 s.
    static let signsRetrySeconds = 3.0
    static let signsRetryMaxSeconds = 30.0
    // Trip recording: arrival, and the GPS steps drive time trusts.
    static let arriveMeters = 45.0
    static let stepMeters: ClosedRange<Double> = 1...250
    // Drive-time accounting: moving above ~5 km/h, gaps over 10 s ignored, synced each minute.
    static let driveMinSpeedMps = 1.5
    static let driveMaxGapSeconds = 10.0
    static let driveFlushSeconds = 60.0
    static let offRouteMeters = 45.0
    static let recalcCooldownSeconds = 2.5
    /// After a failed recalculation the wait doubles, up to this.
    static let recalcWaitMaxSeconds = 60.0
    /// Driving this far since the last recalculation earns another one.
    static let recalcMinMoveMeters = 150.0
    /// Before the route is joined: clearly driving (18 km/h) and this far from the last try.
    static let recalcStartSpeedMps = 5.0
    static let recalcStartMoveMeters = 300.0
    /// A route never joined and nobody driving: the trip is dropped after this.
    static let tripAbandonSeconds = 30.0 * 60
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
