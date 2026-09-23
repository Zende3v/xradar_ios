import SwiftUI

extension View {
    /// Opaque content card (lists, stats tiles), as on Android.
    func xrCard(padding: CGFloat = EonaSpacing.lg, radius: CGFloat = EonaRadius.xl) -> some View {
        self
            .padding(padding)
            .background(EonaColor.surfaceElevated, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(EonaColor.border, lineWidth: 1)
            }
    }

    /// A pale block on a Liquid Glass sheet: it gathers a few controls and keeps them legible,
    /// while the glass still shows around it — never glass laid on glass.
    func xrSheetCard(padding: CGFloat = EonaSpacing.lg, radius: CGFloat = EonaRadius.xl) -> some View {
        self
            .padding(padding)
            .background(EonaColor.surface.opacity(0.5), in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(EonaColor.border, lineWidth: 1)
            }
    }

    /// Liquid Glass panel, for what floats over the map (banners, the dock, alerts).
    func xrGlassPanel(padding: CGFloat = EonaSpacing.lg, radius: CGFloat = EonaRadius.xl) -> some View {
        self
            .padding(padding)
            .glassEffect(.regular, in: .rect(cornerRadius: radius))
    }
}

/// List row: tinted icon tile (or, with [glow], a white glowing icon on a dark tile), title,
/// optional subtitle, trailing content. Placed in a native List or Form section, which gives the
/// grouped iOS look the Android list groups imitate.
struct EonaListRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: EonaIconImage? = nil
    var tint: Color = EonaColor.textSecondary
    var glow = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: EonaSpacing.md) {
            if let icon, glow {
                EonaGlowTile(icon: icon)
            } else if let icon {
                EonaIconView(icon: icon, size: 18)
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.16), in: .rect(cornerRadius: EonaRadius.sm))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.xrBody)
                    .foregroundStyle(EonaColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textTertiary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension EonaListRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, icon: EonaIconImage? = nil, tint: Color = EonaColor.textSecondary, glow: Bool = false) {
        self.init(title: title, subtitle: subtitle, icon: icon, tint: tint, glow: glow) { EmptyView() }
    }
}

/// An icon in one color with a soft halo of that color around its shape.
struct EonaGlowIcon: View {
    let icon: EonaIconImage
    let tint: Color
    var size: CGFloat = 24
    var glowRadius: CGFloat = 4
    var glowOpacity: Double = 0.5

    var body: some View {
        EonaIconView(icon: icon, size: size)
            .foregroundStyle(tint)
            .shadow(color: tint.opacity(glowOpacity), radius: glowRadius)
    }
}

/// A white icon glowing on a dark tile, the same in light and dark: the report picker's look,
/// used for the Menu's icons.
struct EonaGlowTile: View {
    let icon: EonaIconImage
    var size: CGFloat = 30
    var iconSize: CGFloat = 18
    var radius: CGFloat = EonaRadius.sm

    var body: some View {
        EonaGlowIcon(icon: icon, tint: EonaColor.glowIcon, size: iconSize, glowRadius: max(iconSize / 6, 3))
            .frame(width: size, height: size)
            .background(EonaColor.glowTile, in: .rect(cornerRadius: radius))
    }
}

/// Centered spinner with an optional label.
struct EonaLoadingState: View {
    var label: String? = nil

    var body: some View {
        VStack(spacing: EonaSpacing.md) {
            ProgressView()
                .controlSize(.large)
                .tint(EonaColor.accent)
            if let label {
                Text(label)
                    .font(.xrCallout)
                    .foregroundStyle(EonaColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Centered full-area state: icon on a tinted tile, title, message and up to two actions. The
/// one template for empty, error, permission and onboarding states.
struct EonaMessageState: View {
    let icon: EonaIconImage
    let title: String
    let message: String
    var tint: Color = EonaColor.textTertiary
    var primaryLabel: String? = nil
    var onPrimary: (() -> Void)? = nil
    var secondaryLabel: String? = nil
    var onSecondary: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: EonaSpacing.md) {
            EonaIconView(icon: icon, size: 40)
                .foregroundStyle(tint)
                .frame(width: 88, height: 88)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: EonaRadius.xxl))
            Text(title)
                .font(.xrTitle)
                .foregroundStyle(EonaColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.xrCallout)
                .foregroundStyle(EonaColor.textSecondary)
                .multilineTextAlignment(.center)
            if let primaryLabel, let onPrimary {
                EonaButton(title: primaryLabel, fillWidth: true, action: onPrimary)
                    .padding(.top, EonaSpacing.sm)
            }
            if let secondaryLabel, let onSecondary {
                EonaButton(title: secondaryLabel, variant: .ghost, fillWidth: true, action: onSecondary)
            }
        }
        .frame(maxWidth: 360)
        .padding(EonaSpacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
