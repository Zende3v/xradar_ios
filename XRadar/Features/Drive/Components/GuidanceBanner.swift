import SwiftUI
import XRadarCore

/// Top-of-HUD turn card: the maneuver arrow, the distance to it and the road turned onto.
struct GuidanceBanner: View {
    let instruction: GuidanceInstruction

    var body: some View {
        HStack(spacing: XRadarSpacing.md) {
            XRadarIconView(icon: instruction.maneuver.icon, size: 34)
                .foregroundStyle(XRadarColor.accent)
                .frame(width: 52, height: 52)
                .background(XRadarColor.accent.opacity(0.16), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(GuidanceText.distanceLabel(instruction.distanceMeters))
                    .font(.xrTitleLarge.monospacedDigit())
                    .foregroundStyle(XRadarColor.textPrimary)
                Text(instruction.roadName ?? instruction.primaryText)
                    .font(.xrSubhead)
                    .foregroundStyle(XRadarColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .xrGlassPanel(padding: XRadarSpacing.md, radius: XRadarRadius.lg)
        .accessibilityElement(children: .combine)
    }
}
