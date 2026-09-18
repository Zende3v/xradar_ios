import Foundation
import XRadarCore
import XRadarData

extension XRadarData.MapStyle {
    /// Whether the map draws at night: "Auto" follows the sky where the driver is (Paris's before
    /// the first fix), "Clair" and "Sombre" are pinned. The HUD over the map follows the same.
    func isDark(at location: LocationSample?, now: Date = Date()) -> Bool {
        switch self {
        case .auto: !SunClock.isDaylight(lat: location?.latitude ?? 48.8566, lon: location?.longitude ?? 2.3522, at: now)
        case .bright: false
        case .dark: true
        }
    }
}
