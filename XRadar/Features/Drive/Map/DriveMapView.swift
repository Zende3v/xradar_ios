import MapKit
import SwiftUI
import XRadarCore
import XRadarData

/// What the map shows besides the driver.
struct DriveMapContent: Equatable {
    var radars: [Radar] = []
    var reports: [UserReport] = []
    var zones: [RadarZone] = []
    var signs: [RoadSign] = []
    var routePoints: [GeoPoint] = []
}

/// The map, on Apple's MapKit ("Plans"): the route, radar-car zones, control zones, road signs,
/// radars and reports, and the driver's arrow on top. It follows the driver (close,
/// tilted 45°, course up) until a gesture, snaps the arrow onto the route and hides the part
/// already driven. "Auto" switches day and night with the sun where the driver is.
struct DriveMapView: UIViewRepresentable {
    var location: LocationSample?
    var content: DriveMapContent
    var following: Bool
    var mapStyle: XRadarData.MapStyle
    var onUserGesture: () -> Void
    var onReportTap: ((String) -> Void)? = nil

    func makeCoordinator() -> DriveMapCoordinator {
        DriveMapCoordinator(mapStyle: mapStyle)
    }

    func makeUIView(context: Context) -> MKMapView {
        context.coordinator.makeMapView()
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onUserGesture = onUserGesture
        coordinator.onReportTap = onReportTap
        coordinator.update(location: location, content: content, following: following, mapStyle: mapStyle)
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: DriveMapCoordinator) {
        coordinator.stop()
    }
}

/// Owns the MapKit view: overlays, markers, taps, and the 60 fps loop that moves the arrow and the
/// camera. Everything runs on the main thread.
final class DriveMapCoordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
    var onUserGesture: () -> Void = {}
    var onReportTap: ((String) -> Void)?

    private weak var mapView: MKMapView?
    private var displayLink: CADisplayLink?

    private var mapStyle: XRadarData.MapStyle
    private var dark: Bool?
    private var lastSunCheck = Date.distantPast
    private var lastAttributionCheck = Date.distantPast

    private var location: LocationSample?
    private var following = true
    private var content = DriveMapContent()

    // Route: measurable path, overlays and their renderers (the driven part is hidden with strokeStart).
    private var routePath: RoutePath?
    private var routeTrim: RouteTrim?
    private var routeVersion = 0
    private var routeOverlays: [MKPolyline] = []
    private var routeRenderers: [MKPolylineRenderer] = []
    private var trimmedFraction: CGFloat = -1
    private var zoneOverlays: [MKCircle] = []
    private var controlOverlays: [MKPolyline] = []

    // Markers by key, per group, so a refresh only adds and removes what changed.
    private var radarMarkers: [String: MarkerAnnotation] = [:]
    private var reportMarkers: [String: MarkerAnnotation] = [:]
    private var signMarkers: [String: MarkerAnnotation] = [:]
    private var images: [String: UIImage] = [:]
    private var alertBadge: UIImage?
    private var signBadge: UIImage?

    private let driver = DriverAnnotation()
    private var driverAdded = false
    private weak var driverView: DriverView?

    // Map matching, updated per fix, read per frame.
    private var targetAlong = 0.0
    private var onRoute = false
    private var speedMps = 0.0
    private var fixAt = Date.distantPast

    // Render loop.
    private var displayedAlong = 0.0
    private var drawnRouteVersion = -1
    private var arrowLat = 0.0
    private var arrowLon = 0.0
    private var arrowBearing = 0.0
    private var lastRouteTrim = Date.distantPast
    private var seededArrow = false
    private var firstFollow = true
    private var camLat = 0.0
    private var camLon = 0.0
    private var camBearing = 0.0
    private var camDistance = Tuning.navDistance
    private var camTilt = 0.0

    init(mapStyle: XRadarData.MapStyle) {
        self.mapStyle = mapStyle
        super.init()
    }

    func makeMapView() -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = self
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic)
        // Course up and a recenter button: no compass (Arthur's choice), no scale.
        map.showsCompass = false
        map.showsScale = false
        map.isPitchEnabled = false
        mapView = map
        applyDayNight()
        buildImages(traits: map.traitCollection)

        // Any gesture on the map stops the follow mode; the map keeps its own gestures.
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(userGesture(_:)))
        doubleTap.numberOfTapsRequired = 2
        let recognizers: [UIGestureRecognizer] = [
            UIPanGestureRecognizer(target: self, action: #selector(userGesture(_:))),
            UIPinchGestureRecognizer(target: self, action: #selector(userGesture(_:))),
            UIRotationGestureRecognizer(target: self, action: #selector(userGesture(_:))),
            doubleTap,
        ]
        for recognizer in recognizers {
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesEnded = false
            map.addGestureRecognizer(recognizer)
        }

        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        return map
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func update(location newLocation: LocationSample?, content newContent: DriveMapContent, following newFollowing: Bool, mapStyle newStyle: XRadarData.MapStyle) {
        following = newFollowing
        if newStyle != mapStyle {
            mapStyle = newStyle
            applyDayNight()
        }

        let routeChanged = newContent.routePoints != content.routePoints
        if routeChanged {
            routePath = newContent.routePoints.count >= 2 ? RoutePath(points: newContent.routePoints) : nil
            routeVersion += 1
            setRoute(newContent.routePoints)
        }
        let fixChanged = newLocation != location
        location = newLocation
        if let fix = newLocation, fixChanged || routeChanged {
            if fixChanged {
                speedMps = fix.speedMps ?? 0
                fixAt = Date()
            }
            if let path = routePath, let match = path.match(lat: fix.latitude, lon: fix.longitude), match.offRouteMeters <= Tuning.onRouteMeters {
                targetAlong = match.alongMeters
                onRoute = true
            } else {
                onRoute = false
            }
        }

        let previous = content
        content = newContent
        if newContent.radars != previous.radars {
            sync(&radarMarkers, with: newContent.radars.map { radar in
                MarkerAnnotation(key: "r\(radar.id)", image: Self.markerName(radar.alertType), kind: .radars, lat: radar.lat, lon: radar.lon)
            })
        }
        if newContent.reports != previous.reports {
            sync(&reportMarkers, with: newContent.reports.map { report in
                MarkerAnnotation(key: "p\(report.id)", image: Self.markerName(report.type.alertType), kind: .reports, lat: report.lat, lon: report.lon, reportId: report.id)
            })
            setControlZones()
        }
        if newContent.zones != previous.zones {
            setZones()
        }
        if newContent.signs != previous.signs {
            sync(&signMarkers, with: newContent.signs.map { sign in
                let image = sign.type == .speedLimit ? "sp-\(Self.snapSpeed(sign.speed))" : "s-\(sign.type.rawValue)"
                return MarkerAnnotation(key: "s\(sign.type.rawValue)\(sign.lat),\(sign.lon)", image: image, kind: .signs, lat: sign.lat, lon: sign.lon)
            })
        }
    }

    // MARK: Day and night

    /// "Auto" follows the sky where the driver is, not the app theme.
    private func computeDark() -> Bool {
        switch mapStyle {
        case .auto:
            lastSunCheck = Date()
            return !SunClock.isDaylight(lat: location?.latitude ?? Tuning.fallbackLat, lon: location?.longitude ?? Tuning.fallbackLon)
        case .bright:
            return false
        case .dark:
            return true
        }
    }

    private func applyDayNight() {
        let wanted = computeDark()
        guard wanted != dark, let mapView else { return }
        dark = wanted
        mapView.overrideUserInterfaceStyle = wanted ? .dark : .light
    }

    // MARK: Overlays

    private func setRoute(_ points: [GeoPoint]) {
        guard let mapView else { return }
        mapView.removeOverlays(routeOverlays)
        routeOverlays = []
        routeRenderers = []
        trimmedFraction = -1
        guard points.count >= 2 else {
            routeTrim = nil
            return
        }
        let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let glow = MKPolyline(coordinates: coordinates, count: coordinates.count)
        glow.title = Ids.routeGlow
        let core = MKPolyline(coordinates: coordinates, count: coordinates.count)
        core.title = Ids.routeCore
        // At the bottom of the overlays: zones and control zones stay above the route.
        mapView.insertOverlay(glow, at: 0, level: .aboveRoads)
        mapView.insertOverlay(core, at: 1, level: .aboveRoads)
        routeOverlays = [glow, core]
        routeTrim = RouteTrim(points: points)
    }

    /// Hides the route behind [along] metres (nil: the whole route shows, driver off it).
    private func trimRoute(atMeters along: Double?) {
        let fraction = along.flatMap { routeTrim?.fraction(atMeters: $0) } ?? 0
        guard abs(fraction - trimmedFraction) > 0.00005 else { return }
        trimmedFraction = fraction
        for renderer in routeRenderers {
            renderer.strokeStart = fraction
            renderer.setNeedsDisplay()
        }
    }

    private func setZones() {
        guard let mapView else { return }
        mapView.removeOverlays(zoneOverlays)
        zoneOverlays = content.zones.map { zone in
            MKCircle(center: CLLocationCoordinate2D(latitude: zone.lat, longitude: zone.lon), radius: zone.radiusMeters)
        }
        mapView.addOverlays(zoneOverlays, level: .aboveRoads)
    }

    /// A control zone is a stretch of road: the 80 m it covers along the reporter's course.
    private func setControlZones() {
        guard let mapView else { return }
        mapView.removeOverlays(controlOverlays)
        controlOverlays = content.reports.compactMap { report in
            guard report.type == .controlZone, let bearing = report.bearingDeg else { return nil }
            let half = Tuning.controlZoneLength / 2
            let course = bearing * .pi / 180
            let dLat = half * cos(course) / 111_320
            let dLon = half * sin(course) / (111_320 * max(cos(report.lat * .pi / 180), 0.1))
            let coordinates = [
                CLLocationCoordinate2D(latitude: report.lat - dLat, longitude: report.lon - dLon),
                CLLocationCoordinate2D(latitude: report.lat + dLat, longitude: report.lon + dLon),
            ]
            let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
            line.title = Ids.control
            return line
        }
        mapView.addOverlays(controlOverlays, level: .aboveRoads)
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
        let traits = mapView.traitCollection
        if let circle = overlay as? MKCircle {
            let color = UIColor(XRadarColor.radarMobile).resolvedColor(with: traits)
            let renderer = MKCircleRenderer(circle: circle)
            renderer.fillColor = color.withAlphaComponent(0.16)
            renderer.strokeColor = color.withAlphaComponent(0.85)
            renderer.lineWidth = 2
            return renderer
        }
        guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
        let renderer = MKPolylineRenderer(polyline: line)
        renderer.lineCap = .round
        renderer.lineJoin = .round
        if line.title == Ids.routeGlow {
            renderer.strokeColor = MapImages.accent.withAlphaComponent(0.35)
            renderer.lineWidth = 12
            routeRenderers.append(renderer)
        } else if line.title == Ids.routeCore {
            renderer.strokeColor = MapImages.rgb(0x3EE1EC)
            renderer.lineWidth = 5
            routeRenderers.append(renderer)
        } else {
            renderer.strokeColor = UIColor(XRadarColor.controlZone).resolvedColor(with: traits).withAlphaComponent(0.65)
            renderer.lineWidth = 9
        }
        if trimmedFraction > 0, routeRenderers.last === renderer {
            renderer.strokeStart = trimmedFraction
        }
        return renderer
    }

    // MARK: Markers

    /// Adds and removes only what changed; a marker that moved keeps its view.
    private func sync(_ markers: inout [String: MarkerAnnotation], with fresh: [MarkerAnnotation]) {
        guard let mapView else { return }
        var next: [String: MarkerAnnotation] = [:]
        var added: [MarkerAnnotation] = []
        var removed: [MarkerAnnotation] = []
        for marker in fresh where next[marker.key] == nil {
            if let current = markers[marker.key], current.image == marker.image {
                if current.coordinate.latitude != marker.coordinate.latitude || current.coordinate.longitude != marker.coordinate.longitude {
                    current.coordinate = marker.coordinate
                }
                next[marker.key] = current
            } else {
                if let current = markers[marker.key] {
                    removed.append(current)
                }
                next[marker.key] = marker
                added.append(marker)
            }
        }
        for (key, current) in markers where next[key] == nil {
            removed.append(current)
        }
        mapView.removeAnnotations(removed)
        mapView.addAnnotations(added)
        markers = next
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        if let cluster = annotation as? MKClusterAnnotation {
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: Ids.cluster) as? ClusterView
                ?? ClusterView(annotation: cluster, reuseIdentifier: Ids.cluster)
            view.render = { [weak self] cluster in self?.clusterImage(cluster) }
            view.annotation = cluster
            view.displayPriority = .required
            view.zPriority = MKAnnotationViewZPriority(rawValue: Tuning.clusterZ)
            return view
        }
        if annotation is DriverAnnotation {
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: Ids.driver) as? DriverView
                ?? DriverView(annotation: annotation, reuseIdentifier: Ids.driver)
            view.annotation = annotation
            view.displayPriority = .required
            view.zPriority = .max
            view.collisionMode = .none
            driverView = view
            return view
        }
        guard let marker = annotation as? MarkerAnnotation else { return nil }
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: Ids.marker)
            ?? MKAnnotationView(annotation: marker, reuseIdentifier: Ids.marker)
        view.annotation = marker
        view.image = images[marker.image]
        view.canShowCallout = false
        view.clusteringIdentifier = marker.kind.rawValue
        view.displayPriority = marker.kind == .signs ? .defaultHigh : .required
        view.zPriority = MKAnnotationViewZPriority(rawValue: marker.kind.zPriority)
        return view
    }

    /// A pack of markers: the badge with its count beside it, readable on both basemaps.
    private func clusterImage(_ cluster: MKClusterAnnotation) -> (image: UIImage, offset: CGPoint) {
        let signs = (cluster.memberAnnotations.first as? MarkerAnnotation)?.kind == .signs
        let badge = signs ? signBadge : alertBadge
        let image = MapImages.cluster(badge: badge, count: Self.abbreviated(cluster.memberAnnotations.count), dark: dark ?? false)
        // The badge, not the whole picture, sits on the cluster's position.
        return (image, CGPoint(x: (image.size.width - (badge?.size.width ?? image.size.width)) / 2, y: 0))
    }

    // MARK: Taps

    func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
        mapView.deselectAnnotation(annotation, animated: false)
        if let cluster = annotation as? MKClusterAnnotation {
            mapView.showAnnotations(cluster.memberAnnotations, animated: true)
            return
        }
        if let marker = annotation as? MarkerAnnotation, let id = marker.reportId {
            onReportTap?(id)
        }
    }

    @objc private func userGesture(_ recognizer: UIGestureRecognizer) {
        if recognizer.state == .began || recognizer.state == .recognized {
            onUserGesture()
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    // MARK: Render loop

    @objc private func step(_ link: CADisplayLink) {
        guard let mapView else { return }
        let now = Date()
        if now.timeIntervalSince(lastAttributionCheck) > Tuning.attributionCheckInterval {
            lastAttributionCheck = now
            hideAttribution(in: mapView, depth: 0)
        }
        guard let fix = location else { return }
        if mapStyle == .auto, now.timeIntervalSince(lastSunCheck) > Tuning.sunCheckInterval {
            applyDayNight()
        }
        if !seededArrow {
            arrowLat = fix.latitude
            arrowLon = fix.longitude
            seededArrow = true
        }
        if routeVersion != drawnRouteVersion {
            drawnRouteVersion = routeVersion
            displayedAlong = targetAlong
        }

        if let path = routePath, onRoute {
            // Dead reckoning: GPS lands once a second, the eye needs sixty. Between fixes the arrow
            // keeps advancing at the last speed and glides onto the real position when it arrives.
            let elapsed = min(max(now.timeIntervalSince(fixAt), 0), Tuning.maxDeadReckoning)
            let predicted = targetAlong + speedMps * elapsed
            let delta = predicted - displayedAlong
            displayedAlong += delta * (delta >= 0 ? Tuning.alongLerp : Tuning.backLerp)
            let pose = path.pose(at: displayedAlong)
            arrowLat = pose.point.lat
            arrowLon = pose.point.lon
            arrowBearing = Self.lerpAngle(arrowBearing, pose.bearingDeg, Tuning.tangentLerp)
            if now.timeIntervalSince(lastRouteTrim) > Tuning.routeTrimInterval {
                lastRouteTrim = now
                trimRoute(atMeters: displayedAlong)
            }
        } else {
            // Same trick off the route: project the last fix along its course.
            let moving = (fix.speedMps ?? 0) > Tuning.minSpeed
            var targetLat = fix.latitude
            var targetLon = fix.longitude
            if moving, let course = fix.bearingDeg {
                let elapsed = min(max(now.timeIntervalSince(fixAt), 0), Tuning.maxDeadReckoning)
                let travelled = speedMps * elapsed
                let radians = course * .pi / 180
                targetLat += travelled * cos(radians) / 111_320
                targetLon += travelled * sin(radians) / (111_320 * cos(fix.latitude * .pi / 180))
            }
            arrowLat += (targetLat - arrowLat) * Tuning.positionLerp
            arrowLon += (targetLon - arrowLon) * Tuning.positionLerp
            // North up when stopped (a still phone has no reliable course), the GPS course when moving.
            arrowBearing = moving ? (fix.bearingDeg ?? arrowBearing) : 0
            if routePath != nil, now.timeIntervalSince(lastRouteTrim) > Tuning.routeTrimInterval {
                lastRouteTrim = now
                trimRoute(atMeters: nil) // the whole route until the driver is back on it
            }
        }

        driver.coordinate = CLLocationCoordinate2D(latitude: arrowLat, longitude: arrowLon)
        if !driverAdded {
            driverAdded = true
            mapView.addAnnotation(driver)
        }

        if following {
            if firstFollow {
                // Snap on the very first frame so the map opens already upright.
                firstFollow = false
                camLat = arrowLat
                camLon = arrowLon
                camDistance = Tuning.navDistance
                camTilt = Tuning.navTilt
                camBearing = arrowBearing
            }
            camLat += (arrowLat - camLat) * Tuning.positionLerp
            camLon += (arrowLon - camLon) * Tuning.positionLerp
            camDistance += (Tuning.navDistance - camDistance) * Tuning.easeLerp
            camTilt += (Tuning.navTilt - camTilt) * Tuning.easeLerp
            camBearing = Self.lerpAngle(camBearing, arrowBearing, Tuning.bearingLerp)
            let camera = MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: camLat, longitude: camLon),
                fromDistance: camDistance,
                pitch: CGFloat(camTilt),
                heading: camBearing
            )
            mapView.setCamera(camera, animated: false)
        } else {
            // Track the driver's own view, so recentering eases from where they left it.
            let camera = mapView.camera
            camLat = camera.centerCoordinate.latitude
            camLon = camera.centerCoordinate.longitude
            camBearing = camera.heading
            camDistance = camera.centerCoordinateDistance
            camTilt = Double(camera.pitch)
        }

        // The arrow's heading is drawn relative to the map's own.
        driverView?.point(towardDegrees: arrowBearing - mapView.camera.heading)
    }

    /// MapKit's own Plans logo and legal link give way to the tiny credits the HUD draws at the
    /// bottom (DriveScreen), also in Menu > Mentions légales (Arthur's choice). MapKit has no option
    /// for it: its views are hidden by name, checked again as it lays them out.
    private func hideAttribution(in view: UIView, depth: Int) {
        for subview in view.subviews {
            let name = String(describing: type(of: subview))
            if name.contains("Attribution") || name.contains("Logo") || name.contains("Legal") {
                subview.isHidden = true
            } else if depth < 2 {
                hideAttribution(in: subview, depth: depth + 1)
            }
        }
    }

    // MARK: Images

    private func buildImages(traits: UITraitCollection) {
        func color(_ value: Color) -> UIColor {
            UIColor(value).resolvedColor(with: traits)
        }
        let size = CGSize(width: Tuning.markerSize, height: Tuning.markerSize)
        for type in AlertType.allCases {
            let png = Self.pngMarker(type).flatMap { MapImages.scaled($0, to: size) }
            images[Self.markerName(type)] = png ?? vectorMarker(type, color: color)
        }
        for type in SignType.allCases where type != .speedLimit {
            images["s-\(type.rawValue)"] = MapImages.sign(type, size: MapImages.signSize)
        }
        for value in SpeedLimits.values {
            images["sp-\(value)"] = MapImages.speedSign(value, size: MapImages.signSize)
        }
        alertBadge = MapImages.badge("cluster_alert", height: 34)
        signBadge = MapImages.badge("cluster_sign", height: 30)
    }

    private func vectorMarker(_ type: AlertType, color: (Color) -> UIColor) -> UIImage? {
        let size = Tuning.markerSize
        return switch type {
        case .radarFixed: MapImages.marker(glyph: UIImage(named: XRadarAsset.radar.rawValue), color: color(XRadarColor.radarFixed), size: size)
        case .radarMobile: MapImages.marker(glyph: UIImage(named: XRadarAsset.radar.rawValue), color: color(XRadarColor.radarMobile), size: size)
        case .camera: MapImages.marker(glyph: UIImage(named: XRadarAsset.camera.rawValue), color: color(XRadarColor.radarFixed), size: size)
        case .controlZone: MapImages.marker(glyph: UIImage(named: XRadarAsset.shield.rawValue), color: color(XRadarColor.controlZone), size: size)
        case .hazard: MapImages.marker(glyph: UIImage(systemName: XRadarSymbol.warning.rawValue), color: color(XRadarColor.hazard), size: size)
        case .accident: MapImages.marker(glyph: UIImage(named: XRadarAsset.accident.rawValue), color: color(XRadarColor.hazard), size: size)
        case .roadwork: MapImages.marker(glyph: UIImage(named: XRadarAsset.construction.rawValue), color: color(XRadarColor.controlZone), size: size)
        case .radarCar: nil
        }
    }

    private static func pngMarker(_ type: AlertType) -> String? {
        switch type {
        case .radarFixed: "marker_radar_fix"
        case .radarMobile: "marker_radar_mobile"
        case .camera: "marker_camera"
        case .controlZone: "marker_zone_controle"
        case .hazard: "marker_danger"
        case .accident: "marker_accident"
        case .radarCar: "marker_voiture_radar"
        case .roadwork: nil
        }
    }

    private static func markerName(_ type: AlertType) -> String {
        "m-\(type)"
    }

    // MARK: Helpers

    /// "7", "320", "1.2k", "12k".
    private static func abbreviated(_ count: Int) -> String {
        guard count >= 1000 else { return String(count) }
        let thousands = Double(count) / 1000
        return thousands >= 10 ? "\(Int(thousands))k" : String(format: "%.1fk", thousands)
    }

    private static func snapSpeed(_ speed: Int?) -> Int {
        let target = speed ?? 50
        return SpeedLimits.values.min { abs($0 - target) < abs($1 - target) } ?? 50
    }

    /// Shortest-path interpolation from [from] toward [to] by [t], in degrees.
    private static func lerpAngle(_ from: Double, _ to: Double, _ t: Double) -> Double {
        let diff = (to - from + 540).truncatingRemainder(dividingBy: 360) - 180
        return (from + diff * t + 360).truncatingRemainder(dividingBy: 360)
    }

    private enum Ids {
        static let marker = "xr-marker"
        static let cluster = "xr-cluster"
        static let driver = "xr-driver"
        static let routeGlow = "xr-route-glow"
        static let routeCore = "xr-route-core"
        static let control = "xr-control-zone"
    }

    private enum Tuning {
        /// Camera distance while following: about the street-level view of the Android app.
        static let navDistance = 650.0
        static let navTilt = 45.0
        static let minSpeed = 2.0
        static let markerSize: CGFloat = 25
        static let clusterZ: Float = 600
        // Smoothing per frame at 60 fps.
        static let positionLerp = 0.10
        static let easeLerp = 0.06
        static let bearingLerp = 0.12
        static let tangentLerp = 0.3
        static let sunCheckInterval: TimeInterval = 5 * 60
        static let attributionCheckInterval: TimeInterval = 1
        // Before the first fix the sky is Paris's: only the first seconds of a launch use it.
        static let fallbackLat = 48.8566
        static let fallbackLon = 2.3522
        static let controlZoneLength = 80.0
        static let onRouteMeters = 40.0
        static let alongLerp = 0.12
        static let backLerp = 0.04
        /// Never dead-reckon further than this past the last fix (GPS lost, tunnel…).
        static let maxDeadReckoning: TimeInterval = 2.5
        static let routeTrimInterval: TimeInterval = 0.12
    }
}

/// A marker on the map: its image, its group (clustering and stacking), and for a report the id an
/// admin can tap.
final class MarkerAnnotation: NSObject, MKAnnotation {
    enum Kind: String {
        case radars
        case reports
        case signs

        var zPriority: Float {
            switch self {
            case .signs: 100
            case .radars: 300
            case .reports: 400
            }
        }
    }

    let key: String
    let image: String
    let kind: Kind
    let reportId: String?
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(key: String, image: String, kind: Kind, lat: Double, lon: Double, reportId: String? = nil) {
        self.key = key
        self.image = image
        self.kind = kind
        self.reportId = reportId
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        super.init()
    }
}

/// The driver's position, moved every frame.
final class DriverAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate = CLLocationCoordinate2D()
}

/// The driver: the accent arrow over a soft pulsing halo.
final class DriverView: MKAnnotationView {
    private let halo = CALayer()
    private let arrow = UIImageView(image: MapImages.arrow())

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 56, height: 56)
        halo.frame = CGRect(x: 10, y: 10, width: 36, height: 36)
        halo.cornerRadius = 18
        halo.backgroundColor = MapImages.accent.cgColor
        halo.opacity = 0.18
        layer.addSublayer(halo)
        arrow.frame = CGRect(x: 16, y: 16, width: 24, height: 24)
        addSubview(arrow)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    /// Points the arrow [degrees] clockwise from the top of the screen.
    func point(towardDegrees degrees: Double) {
        arrow.transform = CGAffineTransform(rotationAngle: CGFloat(degrees * .pi / 180))
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        halo.removeAllAnimations()
        guard window != nil else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 16.0 / 18.0
        scale.toValue = 24.0 / 18.0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.26
        fade.toValue = 0.10
        let pulse = CAAnimationGroup()
        pulse.animations = [scale, fade]
        pulse.duration = 0.6
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        halo.add(pulse, forKey: "pulse")
    }
}

/// A cluster: its picture is redrawn whenever MapKit shows it with other members.
final class ClusterView: MKAnnotationView {
    var render: ((MKClusterAnnotation) -> (image: UIImage, offset: CGPoint)?)?

    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let cluster = annotation as? MKClusterAnnotation, let drawn = render?(cluster) else { return }
        image = drawn.image
        centerOffset = drawn.offset
    }
}

/// Where the driven part of the route ends, as a share of the line MapKit draws (in map points,
/// which is what `strokeStart` measures).
private struct RouteTrim {
    private let meters: [Double]
    private let lengths: [Double]

    init(points: [GeoPoint]) {
        var meters = [0.0]
        var lengths = [0.0]
        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]
            meters.append(meters[i - 1] + Geo.haversine(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon))
            let pa = MKMapPoint(CLLocationCoordinate2D(latitude: a.lat, longitude: a.lon))
            let pb = MKMapPoint(CLLocationCoordinate2D(latitude: b.lat, longitude: b.lon))
            lengths.append(lengths[i - 1] + hypot(pb.x - pa.x, pb.y - pa.y))
        }
        self.meters = meters
        self.lengths = lengths
    }

    func fraction(atMeters along: Double) -> CGFloat {
        guard meters.count >= 2, let totalMeters = meters.last, totalMeters > 0, let total = lengths.last, total > 0 else { return 0 }
        let d = min(max(along, 0), totalMeters)
        var low = 0
        var high = meters.count - 2
        while low < high {
            let mid = (low + high + 1) / 2
            if meters[mid] <= d {
                low = mid
            } else {
                high = mid - 1
            }
        }
        let segment = meters[low + 1] - meters[low]
        let t = segment > 0 ? (d - meters[low]) / segment : 0
        return CGFloat((lengths[low] + t * (lengths[low + 1] - lengths[low])) / total)
    }
}
