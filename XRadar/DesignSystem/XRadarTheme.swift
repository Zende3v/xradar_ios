import SwiftUI
import UIKit
import XRadarData

/// XRadar's colors, ported from the Android design system (dark first; the system colors mirror
/// iOS). Every color carries its light and dark variant and follows the interface style.
enum XRadarColor {
    // Layered surfaces: the canvas is the deepest (the map, the void).
    static let canvas = dynamic(light: 0xF6F8FB, dark: 0x06070A)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x0E1014)
    static let surfaceElevated = dynamic(light: 0xFFFFFF, dark: 0x16191F)
    static let surfaceHigh = dynamic(light: 0xFFFFFF, dark: 0x1E222A)
    static let scrim = dynamic(light: 0x000000, dark: 0x000000, lightAlpha: 0.40, darkAlpha: 0.80)

    // Lines
    static let border = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.08)
    static let borderStrong = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.14, darkAlpha: 0.14)
    static let separator = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.12)

    // Foreground
    static let textPrimary = dynamic(light: 0x0A0B0D, dark: 0xF5F7FA)
    static let textSecondary = dynamic(light: 0x54596B, dark: 0xA9B0BC)
    static let textTertiary = dynamic(light: 0x8A8F9C, dark: 0x6C7280)
    static let textDisabled = dynamic(light: 0xB6BAC4, dark: 0x454B55)

    // Brand: cyan, for everything interactive and the route.
    static let accent = dynamic(light: 0x0AA7B4, dark: 0x2CD5E0)
    static let accentPressed = dynamic(light: 0x0B8592, dark: 0x16B7C4)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x062024)

    // Feedback
    static let success = dynamic(light: 0x34C759, dark: 0x30D158)
    static let warning = dynamic(light: 0xFF9500, dark: 0xFF9F0A)
    static let danger = dynamic(light: 0xFF3B30, dark: 0xFF453A)
    static let info = dynamic(light: 0x32ADE6, dark: 0x64D2FF)

    // Road safety
    static let speedSafe = success
    static let speedOver = danger
    static let radarFixed = danger
    static let radarMobile = warning
    static let controlZone = dynamic(light: 0x5856D6, dark: 0x5E5CE6)
    static let hazard = dynamic(light: 0xFFCC00, dark: 0xFFD60A)
    /// Report picker: every category on the same disc, its icon in orange with a soft glow.
    static let reportTile = dynamic(light: 0x302C2C, dark: 0x302C2C)
    static let reportIcon = warning

    private nonisolated static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? XRadarColor.rgb(dark, alpha: darkAlpha)
                : XRadarColor.rgb(light, alpha: lightAlpha)
        })
    }

    private nonisolated static func rgb(_ value: UInt32, alpha: CGFloat) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// The Android type scale on the iOS text styles it was tuned to, so Dynamic Type still applies.
extension Font {
    /// 88 bold with tabular figures: the speed on the HUD.
    static let xrDisplayHero = Font.system(size: 88, weight: .bold).monospacedDigit()
    static let xrDisplay = Font.system(size: 40, weight: .semibold)
    /// 28 semibold.
    static let xrTitleLarge = Font.title.weight(.semibold)
    /// 22 semibold.
    static let xrTitle = Font.title2.weight(.semibold)
    /// 17 semibold.
    static let xrHeadline = Font.headline
    /// 17.
    static let xrBody = Font.body
    /// 17 medium.
    static let xrBodyStrong = Font.body.weight(.medium)
    /// 16.
    static let xrCallout = Font.callout
    /// 15.
    static let xrSubhead = Font.subheadline
    /// 13.
    static let xrFootnote = Font.footnote
    /// 12 medium.
    static let xrCaption = Font.caption.weight(.medium)
    /// 16 semibold: button labels.
    static let xrLabel = Font.callout.weight(.semibold)
    /// 17 medium with tabular figures: speeds, times and distances that must not jitter.
    static let xrNumeric = Font.body.weight(.medium).monospacedDigit()
}

/// 4 pt spacing scale.
enum XRadarSpacing {
    static let hair: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 40
    static let giant: CGFloat = 48
    static let colossal: CGFloat = 64
}

/// Corner radii.
enum XRadarRadius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 18
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

extension ThemeMode {
    /// The scheme the app forces; nil follows the phone.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
