import SwiftUI
import UIKit
import EonaData

/// EONA's colors, ported from the Android design system (dark first; the system colors mirror
/// iOS). Every color carries its light and dark variant and follows the interface style.
enum EonaColor {
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

    // Lecture directe du store observable : SwiftUI suit choix, sans recréer navigation ni carte.
    private static var preferences: PreferencesStore?

    static func usePreferences(_ preferences: PreferencesStore) {
        self.preferences = preferences
    }

    static var accentSelection: AccentColor { preferences?.settings.accent ?? .cyan }

    /// Tracé : accent principal renforcé, jamais dégradé sur route.
    static var accentValue: UInt32 { accentSelection.routeValue }

    static var accentPalette: [Color] {
        accentSelection.paletteValues.map { value in
            dynamic(light: shade(value, 0.72), dark: value)
        }
    }

    static var accentGradient: LinearGradient {
        let colours = accentPalette
        return LinearGradient(colors: colours.count == 1 ? colours + colours : colours, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Petites surfaces : chaque teinte reste visible, sans cinq stops comprimés.
    static var accentControlGradient: LinearGradient {
        let colours = accentSelection.controlPaletteValues.map { value in
            dynamic(light: shade(value, 0.72), dark: value)
        }
        return LinearGradient(colors: colours.count == 1 ? colours + colours : colours, startPoint: .leading, endPoint: .trailing)
    }

    /// Fond actif clair : noir lisible en jour comme en nuit, couleurs préservées sous verre clair.
    static var accentFillGradient: LinearGradient {
        let colours = accentSelection.controlPaletteValues.map { value in Color(uiColor: rgb(value, alpha: 1)) }
        return LinearGradient(colors: colours.count == 1 ? colours + colours : colours, startPoint: .leading, endPoint: .trailing)
    }

    /// On white, a bright colour needs to be taken down a notch to stay readable.
    static var accent: Color {
        let value = accentSelection.value
        return dynamic(light: shade(value, 0.72), dark: value)
    }
    static var accentPressed: Color {
        let value = accentSelection.value
        return dynamic(light: shade(value, 0.58), dark: shade(value, 0.82))
    }
    /// Text and icons laid on the accent: black on a light colour, white on a dark one.
    static var onAccent: Color {
        // Deux palettes claires, y compris variantes jour : texte noir garde contraste sur chaque stop.
        if accentSelection.isMulticolour { return .black }
        let value = accentSelection.value
        return Color(uiColor: UIColor { traits in
            let base = traits.userInterfaceStyle == .dark ? value : EonaColor.shade(value, 0.72)
            return EonaColor.isLight(base) ? UIColor.black : UIColor.white
        })
    }

    // Feedback
    static let success = dynamic(light: 0x34C759, dark: 0x30D158)
    static let warning = dynamic(light: 0xFF9500, dark: 0xFF9F0A)
    static let danger = dynamic(light: 0xFF3B30, dark: 0xFF453A)
    /// The ring of a speed-limit sign: a deep blood red, vivid on the white disc, the same in
    /// light and dark — the system red reads pale there.
    static let limitRing = Color(red: 0xD4 / 255.0, green: 0x00 / 255.0, blue: 0x1C / 255.0)
    static let info = dynamic(light: 0x32ADE6, dark: 0x64D2FF)

    // Road safety
    static let speedSafe = success
    static let speedOver = danger
    static let radarFixed = danger
    static let radarMobile = warning
    static let controlZone = dynamic(light: 0x5856D6, dark: 0x5E5CE6)
    static let hazard = dynamic(light: 0xFFCC00, dark: 0xFFD60A)
    // Menu Signaler (04/10) : teintes sobres sous verre, ni orange ni rouge. Claires en sombre
    // pour la lueur, plus denses en clair pour la lisibilité.
    /// Contrôles : acier minéral.
    static let reportSteel = dynamic(light: 0x4F6D8F, dark: 0x9DB4CE)
    /// Dangers : ambre dépoli.
    static let reportAmber = dynamic(light: 0x9C6B22, dark: 0xE2B56E)
    /// Accident, contresens : orchidée, néon discret.
    static let reportOrchid = dynamic(light: 0x84509F, dark: 0xCB9BE8)
    /// Travaux, personnel : sauge.
    static let reportSage = dynamic(light: 0x4F7462, dark: 0x9CC0AC)
    /// Embouteillage : lavande minérale.
    static let reportLavender = dynamic(light: 0x5F5BA6, dark: 0xADA8E6)
    /// Report picker and Menu: a white icon with a soft glow on a dark tile, same in both themes.
    static let glowTile = dynamic(light: 0x302C2C, dark: 0x302C2C)
    static let glowIcon = Color.white

    private nonisolated static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? EonaColor.rgb(dark, alpha: darkAlpha)
                : EonaColor.rgb(light, alpha: lightAlpha)
        })
    }

    /// The same colour, [factor] as bright (0.72 = a little deeper).
    nonisolated static func shade(_ value: UInt32, _ factor: Double) -> UInt32 {
        let channel = { (shift: UInt32) -> UInt32 in
            UInt32(min(255, max(0, (Double((value >> shift) & 0xFF) * factor).rounded())))
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }

    /// True when black reads better than white on this colour (relative luminance).
    nonisolated static func isLight(_ value: UInt32) -> Bool {
        let r = Double((value >> 16) & 0xFF), g = Double((value >> 8) & 0xFF), b = Double(value & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 150
    }

    nonisolated static func rgb(_ value: UInt32, alpha: CGFloat) -> UIColor {
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
enum EonaSpacing {
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
enum EonaRadius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 18
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}
