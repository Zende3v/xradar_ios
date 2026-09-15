import SwiftUI
import XRadarCore

/// The plans side by side, stacked when the screen is too narrow for both.
struct SubscriptionPlans: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: XRadarSpacing.md) {
                cards
            }
            VStack(spacing: XRadarSpacing.md) {
                cards
            }
        }
    }

    private var cards: some View {
        ForEach(SubscriptionPlan.all) { plan in
            PlanCard(plan: plan)
        }
    }
}

/// One plan: its name, price and period; the longer plan with its saving, outlined.
private struct PlanCard: View {
    let plan: SubscriptionPlan

    var body: some View {
        let saving = plan.savingLabel
        VStack(alignment: .leading, spacing: XRadarSpacing.sm) {
            HStack(spacing: XRadarSpacing.sm) {
                Text(plan.title)
                    .font(.xrHeadline)
                    .foregroundStyle(XRadarColor.textPrimary)
                Spacer(minLength: 0)
                if let saving {
                    XRadarBadge(text: saving, color: XRadarColor.success)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(plan.priceLabel)
                    .font(.xrTitle)
                    .monospacedDigit()
                    .foregroundStyle(XRadarColor.textPrimary)
                Text(plan.periodLabel)
                    .font(.xrSubhead)
                    .foregroundStyle(XRadarColor.textSecondary)
            }
            Text(plan.perMonthLabel ?? "Chaque mois")
                .font(.xrFootnote)
                .foregroundStyle(XRadarColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .xrCard()
        .overlay {
            if saving != nil {
                RoundedRectangle(cornerRadius: XRadarRadius.xl)
                    .strokeBorder(XRadarColor.accent, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// What membership brings, ticked.
struct MembershipBenefits: View {
    private struct Benefit: Identifiable {
        let icon: XRadarIconImage
        let title: String

        var id: String { title }
    }

    private let benefits = [
        Benefit(icon: .symbol(.navigation), title: "Navigation guidée sans limite"),
        Benefit(icon: .asset(.radar), title: "Alertes radars et dangers"),
        Benefit(icon: .asset(.report), title: "Signalements sans limite"),
        Benefit(icon: .symbol(.music), title: "Musique au volant"),
        Benefit(icon: .symbol(.user), title: "Photo de profil"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: XRadarSpacing.md) {
            ForEach(benefits) { benefit in
                HStack(spacing: XRadarSpacing.md) {
                    XRadarGlowTile(icon: benefit.icon)
                    Text(benefit.title)
                        .font(.xrBody)
                        .foregroundStyle(XRadarColor.textPrimary)
                    Spacer(minLength: 0)
                    Image(XRadarSymbol.check)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(XRadarColor.success)
                }
            }
        }
    }
}
