import SwiftUI
import UIKit
import XRadarCore
import XRadarData

extension XRadarData.AppTheme {
    /// Whether the app draws at night: "Auto" follows the sky where the driver is (Paris's before
    /// the first fix), "Jour" and "Nuit" are pinned.
    func isDark(at location: LocationSample?, now: Date = Date()) -> Bool {
        switch self {
        case .auto: !SunClock.isDaylight(lat: location?.latitude ?? 48.8566, lon: location?.longitude ?? 2.3522, at: now)
        case .day: false
        case .night: true
        }
    }
}

/// "Thème général" on the window: every screen, the map and the HUD over it switch together. At
/// "Auto" the sky decides again at each fix and every minute (sunrise with the car parked).
struct AppThemeHost: View {
    let preferences: PreferencesStore
    let location: LocationState

    var body: some View {
        TimelineView(.everyMinute) { context in
            let dark = preferences.settings.theme.isDark(at: location.location, now: context.date)
            WindowTheme(style: dark ? .dark : .light)
        }
    }
}

/// Sets the app's look on the window hosting it, as soon as it is attached (before the first
/// frame) and at every change.
private struct WindowTheme: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> WindowThemeView {
        let view = WindowThemeView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: WindowThemeView, context: Context) {
        view.style = style
    }
}

private final class WindowThemeView: UIView {
    var style: UIUserInterfaceStyle = .unspecified {
        didSet { apply() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        apply()
    }

    private func apply() {
        guard let window, window.overrideUserInterfaceStyle != style else { return }
        window.overrideUserInterfaceStyle = style
    }
}
