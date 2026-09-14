import CoreLocation
import XRadarCore
import XRadarData

/// The phone's GPS for the whole app, like the Android foreground location service: asks
/// "Pendant l'utilisation", then keeps updates flowing, screen locked included (blue pill in the
/// status bar), for as long as the app lives. Swiping the app away stops it.
final class LocationTracker: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private let state: LocationState
    /// Tracking was asked for; it begins as soon as the authorization is there.
    private var wanted = false
    private var running = false

    init(state: LocationState) {
        self.state = state
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        state.setAuthorization(Self.authorization(manager.authorizationStatus))
    }

    /// Starts tracking, asking for the authorization first when it was never asked.
    func start() {
        wanted = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            begin()
        default:
            state.setLost()
        }
    }

    func stop() {
        wanted = false
        guard running else { return }
        running = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        state.reset()
    }

    private func begin() {
        guard wanted, !running else { return }
        running = true
        // Needs the "location" background mode (Info.plist); keeps the fixes coming screen locked.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        state.setAuthorization(Self.authorization(status))
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            begin()
        case .denied, .restricted:
            if running {
                running = false
                manager.stopUpdatingLocation()
            }
            if wanted { state.setLost() }
        default:
            break
        }
    }

    private static func authorization(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: .granted
        case .denied, .restricted: .denied
        default: .notDetermined
        }
    }

    // MARK: CLLocationManagerDelegate (called on the main thread, where the manager was made)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorizationChanged(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let sample = LocationSample(last)
        MainActor.assumeIsolated {
            state.update(sample)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // "Location unknown" is transient: the next fix follows. A refusal is not.
        guard (error as? CLError)?.code == .denied else { return }
        MainActor.assumeIsolated {
            state.setLost()
        }
    }
}

extension LocationSample {
    nonisolated init(_ location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speedMps: location.speed >= 0 ? location.speed : nil,
            bearingDeg: location.course >= 0 ? location.course : nil,
            accuracyM: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            timeMs: Int(location.timestamp.timeIntervalSince1970 * 1000)
        )
    }
}
