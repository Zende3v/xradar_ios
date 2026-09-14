import MapLibre
import SwiftUI
import XRadarCore
import XRadarData

/// What the map shows besides the driver.
struct DriveMapContent: Equatable {
    var radars: [Radar] = []
    var reports: [UserReport] = []
    var zones: [RadarZone] = []
    var liveUsers: [LiveUser] = []
    var signs: [RoadSign] = []
    var routePoints: [GeoPoint] = []
}

/// The real map, like the Android DriveMap: MapLibre drawing the Plans basemap (day or night
/// palette), the route, radar-car zones, road signs, radars, control zones, reports and other
/// drivers, and the driver's arrow on top. It follows the driver (zoom 17.6, tilt 45°, course up)
/// until a gesture, snaps the arrow onto the route and trims the part already driven.
struct DriveMapView: UIViewRepresentable {
    var location: LocationSample?
    var content: DriveMapContent
    var following: Bool
    var mapStyle: MapStyle
    var stadiaAPIKey: String?
    var onUserGesture: () -> Void
    var onReportTap: ((String) -> Void)? = nil

    func makeCoordinator() -> DriveMapCoordinator {
        DriveMapCoordinator(stadiaAPIKey: stadiaAPIKey, mapStyle: mapStyle)
    }

    func makeUIView(context: Context) -> MLNMapView {
        context.coordinator.makeMapView()
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onUserGesture = onUserGesture
        coordinator.onReportTap = onReportTap
        coordinator.update(location: location, content: content, following: following, mapStyle: mapStyle)
    }

    static func dismantleUIView(_ mapView: MLNMapView, coordinator: DriveMapCoordinator) {
        coordinator.stop()
    }
}

/// Owns the MapLibre view: style, layers, data and the 60 fps loop that moves the arrow and the
/// camera. Everything runs on the main thread.
final class DriveMapCoordinator: NSObject, MLNMapViewDelegate {
    var onUserGesture: () -> Void = {}
    var onReportTap: ((String) -> Void)?

    private let stadiaAPIKey: String?
    private weak var mapView: MLNMapView?
    private var displayLink: CADisplayLink?

    private var styleReady = false
    private var dark: Bool?
    private var mapStyle: MapStyle
    private var lastSunCheck = Date.distantPast

    private var location: LocationSample?
    private var following = true
    private var content = DriveMapContent()
    private var routePath: RoutePath?
    private var routeVersion = 0

    // Map matching, updated per fix, read per frame.
    private var targetAlong = 0.0
    private var onRoute = false
    private var speedMps = 0.0
    private var fixAt = Date.distantPast

    // Render loop.
    private var phase = 0.0
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
    private var camZoom = Tuning.navZoom
    private var camTilt = 0.0

    init(stadiaAPIKey: String?, mapStyle: MapStyle) {
        self.stadiaAPIKey = stadiaAPIKey
        self.mapStyle = mapStyle
        super.init()
    }

    func makeMapView() -> MLNMapView {
        // Tiles from earlier drives stay on the phone, so a familiar area comes back at once.
        Self.growAmbientCache()
        let dark = computeDark()
        self.dark = dark
        let map = MLNMapView(frame: .zero, styleURL: try? PlansMapStyle.url(dark: dark, apiKey: stadiaAPIKey))
        map.delegate = self
        map.isPitchEnabled = false
        map.logoView.isHidden = true

        // Taps: a cluster zooms in, a report marker is handed to the screen.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        for recognizer in map.gestureRecognizers ?? [] {
            if let other = recognizer as? UITapGestureRecognizer, other.numberOfTapsRequired == 2 {
                tap.require(toFail: other)
            }
        }
        map.addGestureRecognizer(tap)
        mapView = map

        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        return map
    }

    /// Called outside the main actor: MapLibre may run the completion on any thread.
    nonisolated private static func growAmbientCache() {
        MLNOfflineStorage.shared.setMaximumAmbientCacheSize(200 * 1024 * 1024) { _ in }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func update(location newLocation: LocationSample?, content newContent: DriveMapContent, following newFollowing: Bool, mapStyle newStyle: MapStyle) {
        following = newFollowing
        if newStyle != mapStyle {
            mapStyle = newStyle
            reloadStyleIfNeeded()
        }

        let routeChanged = newContent.routePoints != content.routePoints
        if routeChanged {
            routePath = newContent.routePoints.count >= 2 ? RoutePath(points: newContent.routePoints) : nil
            routeVersion += 1
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
        guard styleReady, let style = mapView?.style else { return }
        if newContent.radars != previous.radars { setRadars(style) }
        if newContent.reports != previous.reports {
            setReports(style)
            setControlZones(style)
        }
        if newContent.zones != previous.zones { setZones(style) }
        if newContent.liveUsers != previous.liveUsers { setLive(style) }
        if newContent.signs != previous.signs { setSigns(style) }
    }

    // MARK: Style

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

    private func reloadStyleIfNeeded() {
        let wanted = computeDark()
        guard wanted != dark, let mapView else { return }
        dark = wanted
        styleReady = false
        mapView.styleURL = try? PlansMapStyle.url(dark: wanted, apiKey: stadiaAPIKey)
    }

    nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        MainActor.assumeIsolated {
            styleLoaded()
        }
    }

    nonisolated func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
        let gestures: MLNCameraChangeReason = [
            .gesturePan, .gesturePinch, .gestureRotate, .gestureZoomIn, .gestureZoomOut, .gestureOneFingerZoom, .gestureTilt,
        ]
        guard !reason.isDisjoint(with: gestures) else { return }
        MainActor.assumeIsolated {
            onUserGesture()
        }
    }

    private func styleLoaded() {
        guard let mapView, let style = mapView.style else { return }
        let traits = mapView.traitCollection
        func color(_ value: Color) -> UIColor {
            UIColor(value).resolvedColor(with: traits)
        }
        let darkMap = dark ?? false

        // Route, at the bottom.
        let route = MLNShapeSource(identifier: Ids.route, shape: nil, options: nil)
        style.addSource(route)
        let glow = MLNLineStyleLayer(identifier: Ids.routeGlow, source: route)
        glow.lineColor = constant(MapImages.accent)
        glow.lineWidth = constant(12)
        glow.lineOpacity = constant(0.35)
        glow.lineCap = constant("round")
        glow.lineJoin = constant("round")
        style.addLayer(glow)
        let core = MLNLineStyleLayer(identifier: Ids.routeCore, source: route)
        core.lineColor = constant(MapImages.rgb(0x3EE1EC))
        core.lineWidth = constant(5)
        core.lineCap = constant("round")
        core.lineJoin = constant("round")
        style.addLayer(core)

        // Radar-car probable zones, above the route.
        let zoneColor = color(XRadarColor.radarMobile)
        let zones = MLNShapeSource(identifier: Ids.zones, shape: nil, options: nil)
        style.addSource(zones)
        let zoneFill = MLNFillStyleLayer(identifier: Ids.zoneFill, source: zones)
        zoneFill.fillColor = constant(zoneColor)
        zoneFill.fillOpacity = constant(0.16)
        style.addLayer(zoneFill)
        let zoneLine = MLNLineStyleLayer(identifier: Ids.zoneLine, source: zones)
        zoneLine.lineColor = constant(zoneColor)
        zoneLine.lineWidth = constant(2)
        zoneLine.lineOpacity = constant(0.85)
        style.addLayer(zoneLine)

        // Alert markers: a drawn marker for every type, replaced by the PNG where there is one.
        let markerSize = CGSize(width: MapImages.markerSize, height: MapImages.markerSize)
        for type in AlertType.allCases {
            if let marker = vectorMarker(type, color: color) {
                style.setImage(marker, forName: Self.markerName(type))
            }
            if let png = Self.pngMarker(type), let marker = MapImages.scaled(png, to: markerSize) {
                style.setImage(marker, forName: Self.markerName(type))
            }
        }
        let alertBadge = MapImages.badge("cluster_alert", height: 34)
        let signBadge = MapImages.badge("cluster_sign", height: 30)
        if let alertBadge { style.setImage(alertBadge, forName: Ids.clusterAlertImage) }
        if let signBadge { style.setImage(signBadge, forName: Ids.clusterSignImage) }

        // Other live drivers (violet).
        style.setImage(MapImages.marker(glyph: MapImages.navigationGlyph(), color: MapImages.rgb(0x8B7CF6)), forName: Ids.liveImage)
        let live = MLNShapeSource(identifier: Ids.live, shape: nil, options: nil)
        style.addSource(live)
        let liveLayer = MLNSymbolStyleLayer(identifier: Ids.liveLayer, source: live)
        liveLayer.iconImageName = constant(Ids.liveImage)
        liveLayer.iconRotation = NSExpression(forKeyPath: "bearing")
        liveLayer.iconRotationAlignment = constant("map")
        liveLayer.iconAllowsOverlap = constant(true)
        liveLayer.iconIgnoresPlacement = constant(true)
        liveLayer.iconScale = constant(0.8)
        style.addLayer(liveLayer)

        // OSM road signs, drawn, a bit larger than alerts; speed signs along the route.
        for type in SignType.allCases where type != .speedLimit {
            style.setImage(MapImages.sign(type, size: MapImages.signSize), forName: "s-\(type.rawValue)")
        }
        for value in SpeedLimits.values {
            style.setImage(MapImages.speedSign(value, size: MapImages.signSize), forName: "sp-\(value)")
        }
        let signs = MLNShapeSource(identifier: Ids.signs, shape: nil, options: Self.clusterOptions)
        style.addSource(signs)
        let signLayer = MLNSymbolStyleLayer(identifier: Ids.signLayer, source: signs)
        signLayer.iconImageName = NSExpression(forKeyPath: "icon")
        signLayer.iconAllowsOverlap = constant(false)
        signLayer.iconScale = constant(1)
        signLayer.predicate = NSPredicate(format: "cluster != YES")
        style.addLayer(signLayer)
        addClusterLayer(style, source: signs, identifier: Ids.signCluster, image: Ids.clusterSignImage, badgeWidth: signBadge?.size.width, darkMap: darkMap)

        // Radars: grouped into counted badges zoomed out, split apart zooming in.
        let radars = MLNShapeSource(identifier: Ids.radars, shape: nil, options: Self.clusterOptions)
        style.addSource(radars)
        style.addLayer(markerLayer(Ids.radarLayer, source: radars))
        addClusterLayer(style, source: radars, identifier: Ids.radarCluster, image: Ids.clusterAlertImage, badgeWidth: alertBadge?.size.width, darkMap: darkMap)

        // A control zone is a stretch of road: the 80 m it covers along the reporter's course.
        let controls = MLNShapeSource(identifier: Ids.controls, shape: nil, options: nil)
        style.addSource(controls)
        let controlLine = MLNLineStyleLayer(identifier: Ids.controlLayer, source: controls)
        controlLine.lineColor = constant(color(XRadarColor.controlZone))
        controlLine.lineWidth = constant(9)
        controlLine.lineOpacity = constant(0.65)
        controlLine.lineCap = constant("round")
        style.addLayer(controlLine)

        // Reports, above radars.
        let reports = MLNShapeSource(identifier: Ids.reports, shape: nil, options: Self.clusterOptions)
        style.addSource(reports)
        style.addLayer(markerLayer(Ids.reportLayer, source: reports))
        addClusterLayer(style, source: reports, identifier: Ids.reportCluster, image: Ids.clusterAlertImage, badgeWidth: alertBadge?.size.width, darkMap: darkMap)

        // The driver on top: a soft pulsing halo and the arrow.
        style.setImage(MapImages.arrow(), forName: Ids.arrowImage)
        let position = MLNShapeSource(identifier: Ids.position, shape: nil, options: nil)
        style.addSource(position)
        let halo = MLNCircleStyleLayer(identifier: Ids.positionHalo, source: position)
        halo.circleRadius = constant(18)
        halo.circleColor = constant(MapImages.accent)
        halo.circleOpacity = constant(0.18)
        style.addLayer(halo)
        let arrow = MLNSymbolStyleLayer(identifier: Ids.positionArrow, source: position)
        arrow.iconImageName = constant(Ids.arrowImage)
        arrow.iconRotation = NSExpression(forKeyPath: "bearing")
        arrow.iconRotationAlignment = constant("map")
        arrow.iconAllowsOverlap = constant(true)
        arrow.iconIgnoresPlacement = constant(true)
        arrow.iconScale = constant(0.85)
        style.addLayer(arrow)

        if let fix = location {
            setArrow(style, lat: fix.latitude, lon: fix.longitude, bearing: 0)
        }
        setRadars(style)
        setReports(style)
        setControlZones(style)
        setZones(style)
        setLive(style)
        setSigns(style)
        setRoute(style, content.routePoints)

        // The loop starts over with the new style, as on Android.
        let camera = mapView.camera
        camLat = camera.centerCoordinate.latitude
        camLon = camera.centerCoordinate.longitude
        camBearing = camera.heading
        camZoom = mapView.zoomLevel > 1 ? mapView.zoomLevel : Tuning.navZoom
        camTilt = Double(camera.pitch)
        drawnRouteVersion = -1
        seededArrow = false
        firstFollow = true
        styleReady = true
    }

    private func markerLayer(_ identifier: String, source: MLNSource) -> MLNSymbolStyleLayer {
        let layer = MLNSymbolStyleLayer(identifier: identifier, source: source)
        layer.iconImageName = NSExpression(forKeyPath: "icon")
        layer.iconAllowsOverlap = constant(true)
        layer.iconIgnoresPlacement = constant(true)
        layer.iconScale = constant(0.82)
        layer.predicate = NSPredicate(format: "cluster != YES")
        return layer
    }

    /// A pack of markers: the badge with its count beside it, readable on both basemaps.
    private func addClusterLayer(_ style: MLNStyle, source: MLNSource, identifier: String, image: String, badgeWidth: CGFloat?, darkMap: Bool) {
        let layer = MLNSymbolStyleLayer(identifier: identifier, source: source)
        layer.predicate = NSPredicate(format: "cluster == YES")
        layer.iconImageName = constant(image)
        layer.iconAllowsOverlap = constant(true)
        layer.iconIgnoresPlacement = constant(true)
        layer.text = NSExpression(forKeyPath: "point_count_abbreviated")
        layer.textFontNames = constant(["Stadia Semibold"])
        layer.textFontSize = constant(Tuning.clusterTextSize)
        layer.textColor = constant(darkMap ? UIColor.white : MapImages.rgb(0x0A0B0D))
        layer.textHaloColor = constant(darkMap ? MapImages.rgb(0x06070A) : UIColor.white)
        layer.textHaloWidth = constant(1.8)
        layer.textAnchor = constant("left")
        layer.textOffset = constant(NSValue(cgVector: CGVector(dx: Self.badgeOffsetEm(badgeWidth), dy: 0)))
        layer.textAllowsOverlap = constant(true)
        layer.textIgnoresPlacement = constant(true)
        style.addLayer(layer)
    }

    // MARK: Data

    private func setArrow(_ style: MLNStyle, lat: Double, lon: Double, bearing: Double) {
        shapeSource(style, Ids.position)?.shape = point(lat, lon, ["bearing": bearing])
    }

    private func setRadars(_ style: MLNStyle) {
        let features: [MLNShape & MLNFeature] = content.radars.map { point($0.lat, $0.lon, ["icon": Self.markerName($0.alertType)]) }
        shapeSource(style, Ids.radars)?.shape = MLNShapeCollectionFeature(shapes: features)
    }

    private func setReports(_ style: MLNStyle) {
        let features: [MLNShape & MLNFeature] = content.reports.map { point($0.lat, $0.lon, ["icon": Self.markerName($0.type.alertType), "rid": $0.id]) }
        shapeSource(style, Ids.reports)?.shape = MLNShapeCollectionFeature(shapes: features)
    }

    private func setControlZones(_ style: MLNStyle) {
        let lines: [MLNShape & MLNFeature] = content.reports.compactMap { report -> MLNPolylineFeature? in
            guard report.type == .controlZone, let bearing = report.bearingDeg else { return nil }
            let half = Tuning.controlZoneLength / 2
            let course = bearing * .pi / 180
            let dLat = half * cos(course) / 111_320
            let dLon = half * sin(course) / (111_320 * max(cos(report.lat * .pi / 180), 0.1))
            let coordinates = [
                CLLocationCoordinate2D(latitude: report.lat - dLat, longitude: report.lon - dLon),
                CLLocationCoordinate2D(latitude: report.lat + dLat, longitude: report.lon + dLon),
            ]
            return MLNPolylineFeature(coordinates: coordinates, count: UInt(coordinates.count))
        }
        shapeSource(style, Ids.controls)?.shape = MLNShapeCollectionFeature(shapes: lines)
    }

    private func setZones(_ style: MLNStyle) {
        let polygons: [MLNShape & MLNFeature] = content.zones.map { zone -> MLNPolygonFeature in
            let ring = Self.circle(lat: zone.lat, lon: zone.lon, radius: zone.radiusMeters)
            return MLNPolygonFeature(coordinates: ring, count: UInt(ring.count))
        }
        shapeSource(style, Ids.zones)?.shape = MLNShapeCollectionFeature(shapes: polygons)
    }

    private func setLive(_ style: MLNStyle) {
        let features: [MLNShape & MLNFeature] = content.liveUsers.map { point($0.lat, $0.lon, ["bearing": $0.bearingDeg ?? 0]) }
        shapeSource(style, Ids.live)?.shape = MLNShapeCollectionFeature(shapes: features)
    }

    private func setSigns(_ style: MLNStyle) {
        let features: [MLNShape & MLNFeature] = content.signs.map { sign -> MLNPointFeature in
            let icon = sign.type == .speedLimit ? "sp-\(Self.snapSpeed(sign.speed))" : "s-\(sign.type.rawValue)"
            return point(sign.lat, sign.lon, ["icon": icon])
        }
        shapeSource(style, Ids.signs)?.shape = MLNShapeCollectionFeature(shapes: features)
    }

    private func setRoute(_ style: MLNStyle, _ points: [GeoPoint]) {
        guard let source = shapeSource(style, Ids.route) else { return }
        guard points.count >= 2 else {
            source.shape = MLNShapeCollectionFeature(shapes: [] as [MLNShape & MLNFeature])
            return
        }
        let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        source.shape = MLNPolylineFeature(coordinates: coordinates, count: UInt(coordinates.count))
    }

    private func point(_ lat: Double, _ lon: Double, _ attributes: [String: Any]) -> MLNPointFeature {
        let feature = MLNPointFeature()
        feature.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        feature.attributes = attributes
        return feature
    }

    private func shapeSource(_ style: MLNStyle, _ identifier: String) -> MLNShapeSource? {
        style.source(withIdentifier: identifier) as? MLNShapeSource
    }

    private func constant(_ value: Any) -> NSExpression {
        NSExpression(forConstantValue: value)
    }

    // MARK: Taps

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard styleReady, let mapView else { return }
        let point = recognizer.location(in: mapView)
        let clusters: Set<String> = [Ids.radarCluster, Ids.reportCluster, Ids.signCluster]
        if !mapView.visibleFeatures(at: point, styleLayerIdentifiers: clusters).isEmpty {
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            mapView.setCenter(coordinate, zoomLevel: min(mapView.zoomLevel + Tuning.clusterZoomStep, Tuning.clusterZoomMax), animated: true)
            return
        }
        guard let onReportTap,
              let rid = mapView.visibleFeatures(at: point, styleLayerIdentifiers: [Ids.reportLayer]).first?.attribute(forKey: "rid") as? String
        else { return }
        onReportTap(rid)
    }

    // MARK: Render loop

    @objc private func step(_ link: CADisplayLink) {
        defer { phase += Tuning.pulseStep }
        guard styleReady, let mapView, let style = mapView.style, let fix = location else { return }
        let now = Date()
        if mapStyle == .auto, now.timeIntervalSince(lastSunCheck) > Tuning.sunCheckInterval {
            reloadStyleIfNeeded()
            if !styleReady { return }
        }
        if !seededArrow {
            arrowLat = fix.latitude
            arrowLon = fix.longitude
            seededArrow = true
        }
        if routeVersion != drawnRouteVersion {
            drawnRouteVersion = routeVersion
            displayedAlong = targetAlong
            if routePath == nil { setRoute(style, []) }
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
                setRoute(style, path.trimmed(from: displayedAlong))
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
            if let path = routePath, now.timeIntervalSince(lastRouteTrim) > Tuning.routeTrimInterval {
                lastRouteTrim = now
                setRoute(style, path.points) // the whole route until the driver is back on it
            }
        }

        setArrow(style, lat: arrowLat, lon: arrowLon, bearing: arrowBearing)
        let pulse = (sin(phase) + 1) / 2
        if let halo = style.layer(withIdentifier: Ids.positionHalo) as? MLNCircleStyleLayer {
            halo.circleRadius = constant(16 + 8 * pulse)
            halo.circleOpacity = constant(0.10 + 0.16 * pulse)
        }

        if following {
            if firstFollow {
                // Snap on the very first frame so the map opens already upright.
                firstFollow = false
                camLat = arrowLat
                camLon = arrowLon
                camZoom = Tuning.navZoom
                camTilt = Tuning.navTilt
                camBearing = arrowBearing
            }
            camLat += (arrowLat - camLat) * Tuning.positionLerp
            camLon += (arrowLon - camLon) * Tuning.positionLerp
            camZoom += (Tuning.navZoom - camZoom) * Tuning.easeLerp
            camTilt += (Tuning.navTilt - camTilt) * Tuning.easeLerp
            camBearing = Self.lerpAngle(camBearing, arrowBearing, Tuning.bearingLerp)
            let center = CLLocationCoordinate2D(latitude: camLat, longitude: camLon)
            let altitude = MLNAltitudeForZoomLevel(camZoom, CGFloat(camTilt), camLat, mapView.bounds.size)
            mapView.setCamera(MLNMapCamera(lookingAtCenter: center, altitude: altitude, pitch: CGFloat(camTilt), heading: camBearing), animated: false)
        } else {
            // Track the driver's own view, so recentering eases from where they left it.
            let camera = mapView.camera
            camLat = camera.centerCoordinate.latitude
            camLon = camera.centerCoordinate.longitude
            camBearing = camera.heading
            camZoom = mapView.zoomLevel
            camTilt = Double(camera.pitch)
        }
    }

    // MARK: Helpers

    private func vectorMarker(_ type: AlertType, color: (Color) -> UIColor) -> UIImage? {
        switch type {
        case .radarFixed: MapImages.marker(glyph: UIImage(named: XRadarAsset.radar.rawValue), color: color(XRadarColor.radarFixed))
        case .radarMobile: MapImages.marker(glyph: UIImage(named: XRadarAsset.radar.rawValue), color: color(XRadarColor.radarMobile))
        case .camera: MapImages.marker(glyph: UIImage(named: XRadarAsset.camera.rawValue), color: color(XRadarColor.radarFixed))
        case .controlZone: MapImages.marker(glyph: UIImage(named: XRadarAsset.shield.rawValue), color: color(XRadarColor.controlZone))
        case .hazard: MapImages.marker(glyph: UIImage(systemName: XRadarSymbol.warning.rawValue), color: color(XRadarColor.hazard))
        case .accident: MapImages.marker(glyph: UIImage(named: XRadarAsset.accident.rawValue), color: color(XRadarColor.hazard))
        case .roadwork: MapImages.marker(glyph: UIImage(named: XRadarAsset.construction.rawValue), color: color(XRadarColor.controlZone))
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

    private static let clusterOptions: [MLNShapeSourceOption: Any] = [
        .clustered: true,
        .clusterRadius: Tuning.clusterRadius,
        .maximumZoomLevelForClustering: Tuning.clusterMaxZoom,
    ]

    /// Half the badge plus a small gap, in ems of the count's text size.
    private static func badgeOffsetEm(_ width: CGFloat?) -> Double {
        guard let width, width > 0 else { return 1.2 }
        return (Double(width) / 2 + Tuning.clusterTextGap) / Tuning.clusterTextSize
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

    /// A geodesic circle approximated by a 64-gon, radius in metres.
    private static func circle(lat: Double, lon: Double, radius: Double) -> [CLLocationCoordinate2D] {
        let earth = 6_371_000.0
        let latRadians = lat * .pi / 180
        return (0...64).map { i in
            let theta = 2 * Double.pi * Double(i) / 64
            let dLat = radius * cos(theta) / earth * 180 / .pi
            let dLon = radius * sin(theta) / (earth * cos(latRadians)) * 180 / .pi
            return CLLocationCoordinate2D(latitude: lat + dLat, longitude: lon + dLon)
        }
    }

    private enum Ids {
        static let position = "xr-position"
        static let positionHalo = "xr-position-halo"
        static let positionArrow = "xr-position-arrow"
        static let arrowImage = "xr-arrow"
        static let clusterAlertImage = "xr-cluster-alert"
        static let clusterSignImage = "xr-cluster-sign"
        static let radars = "xr-radars"
        static let radarLayer = "xr-radars-dot"
        static let radarCluster = "xr-radars-cluster"
        static let controls = "xr-control-zones"
        static let controlLayer = "xr-control-zones-line"
        static let reports = "xr-reports"
        static let reportLayer = "xr-reports-dot"
        static let reportCluster = "xr-reports-cluster"
        static let signs = "xr-signs"
        static let signLayer = "xr-signs-dot"
        static let signCluster = "xr-signs-cluster"
        static let live = "xr-live"
        static let liveLayer = "xr-live-dot"
        static let liveImage = "m-live"
        static let zones = "xr-zones"
        static let zoneFill = "xr-zones-fill"
        static let zoneLine = "xr-zones-line"
        static let route = "xr-route"
        static let routeGlow = "xr-route-glow"
        static let routeCore = "xr-route-core"
    }

    private enum Tuning {
        static let navZoom = 17.6
        static let navTilt = 45.0
        static let minSpeed = 2.0
        // Smoothing per frame at 60 fps.
        static let positionLerp = 0.10
        static let easeLerp = 0.06
        static let bearingLerp = 0.12
        static let tangentLerp = 0.3
        static let pulseStep = 0.09
        static let sunCheckInterval: TimeInterval = 5 * 60
        // Before the first fix the sky is Paris's: only the first seconds of a launch use it.
        static let fallbackLat = 48.8566
        static let fallbackLon = 2.3522
        static let clusterMaxZoom = 13
        static let clusterRadius = 62
        static let clusterZoomStep = 1.8
        static let clusterZoomMax = 16.5
        static let clusterTextSize = 14.0
        static let clusterTextGap = 4.0
        static let controlZoneLength = 80.0
        static let onRouteMeters = 40.0
        static let alongLerp = 0.12
        static let backLerp = 0.04
        /// Never dead-reckon further than this past the last fix (GPS lost, tunnel…).
        static let maxDeadReckoning: TimeInterval = 2.5
        static let routeTrimInterval: TimeInterval = 0.12
    }
}
