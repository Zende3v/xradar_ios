import SwiftUI
import EonaCore

/// Top-of-HUD turn card: the maneuver arrow, the distance to it and the road turned onto.
struct GuidanceBanner: View {
    let instruction: GuidanceInstruction

    var body: some View {
        HStack(spacing: EonaSpacing.md) {
            EonaIconView(icon: instruction.maneuver.icon, size: 34)
                .foregroundStyle(EonaColor.accent)
                .frame(width: 52, height: 52)
                .background(EonaColor.accent.opacity(0.16), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(GuidanceText.distanceLabel(instruction.distanceMeters))
                    .font(.xrTitleLarge.monospacedDigit())
                    .foregroundStyle(EonaColor.textPrimary)
                Text(instruction.roadName ?? instruction.primaryText)
                    .font(.xrSubhead)
                    .foregroundStyle(EonaColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .xrGlassPanel(padding: EonaSpacing.md, radius: EonaRadius.lg)
        .accessibilityElement(children: .combine)
    }
}
