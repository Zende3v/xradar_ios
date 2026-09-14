import SwiftUI

extension View {
    /// Opaque content card (lists, stats tiles), as on Android.
    func xrCard(padding: CGFloat = XRadarSpacing.lg, radius: CGFloat = XRadarRadius.xl) -> some View {
        self
            .padding(padding)
            .background(XRadarColor.surfaceElevated, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(XRadarColor.border, lineWidth: 1)
            }
    }

    /// Liquid Glass panel, for what floats over the map (banners, the dock, alerts).
    func xrGlassPanel(padding: CGFloat = XRadarSpacing.lg, radius: CGFloat = XRadarRadius.xl) -> some View {
        self
            .padding(padding)
            .glassEffect(.regular, in: .rect(cornerRadius: radius))
    }
}

/// List row: tinted icon tile, title, optional subtitle, trailing content. Placed in a native
/// List or Form section, which gives the grouped iOS look the Android list groups imitate.
struct XRadarListRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: XRadarIconImage? = nil
    var tint: Color = XRadarColor.textSecondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: XRadarSpacing.md) {
            if let icon {
                XRadarIconView(icon: icon, size: 18)
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.16), in: .rect(cornerRadius: XRadarRadius.sm))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.xrBody)
                    .foregroundStyle(XRadarColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.xrFootnote)
                        .foregroundStyle(XRadarColor.textTertiary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension XRadarListRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, icon: XRadarIconImage? = nil, tint: Color = XRadarColor.textSecondary) {
        self.init(title: title, subtitle: subtitle, icon: icon, tint: tint) { EmptyView() }
    }
}

/// An icon in one color with a soft halo of that color around its shape.
struct XRadarGlowIcon: View {
    let icon: XRadarIconImage
    let tint: Color
    var size: CGFloat = 24
    var glowRadius: CGFloat = 4
    var glowOpacity: Double = 0.5

    var body: some View {
        XRadarIconView(icon: icon, size: size)
            .foregroundStyle(tint)
            .shadow(color: tint.opacity(glowOpacity), radius: glowRadius)
    }
}

/// Centered spinner with an optional label.
struct XRadarLoadingState: View {
    var label: String? = nil

    var body: some View {
        VStack(spacing: XRadarSpacing.md) {
            ProgressView()
                .controlSize(.large)
                .tint(XRadarColor.accent)
            if let label {
                Text(label)
                    .font(.xrCallout)
                    .foregroundStyle(XRadarColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Centered full-area state: icon on a tinted tile, title, message and up to two actions. The
/// one template for empty, error, permission and onboarding states.
struct XRadarMessageState: View {
    let icon: XRadarIconImage
    let title: String
    let message: String
    var tint: Color = XRadarColor.textTertiary
    var primaryLabel: String? = nil
    var onPrimary: (() -> Void)? = nil
    var secondaryLabel: String? = nil
    var onSecondary: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: XRadarSpacing.md) {
            XRadarIconView(icon: icon, size: 40)
                .foregroundStyle(tint)
                .frame(width: 88, height: 88)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: XRadarRadius.xxl))
            Text(title)
                .font(.xrTitle)
                .foregroundStyle(XRadarColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.xrCallout)
                .foregroundStyle(XRadarColor.textSecondary)
                .multilineTextAlignment(.center)
            if let primaryLabel, let onPrimary {
                XRadarButton(title: primaryLabel, fillWidth: true, action: onPrimary)
                    .padding(.top, XRadarSpacing.sm)
            }
            if let secondaryLabel, let onSecondary {
                XRadarButton(title: secondaryLabel, variant: .ghost, fillWidth: true, action: onSecondary)
            }
        }
        .frame(maxWidth: 360)
        .padding(XRadarSpacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
