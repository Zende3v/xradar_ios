import SwiftUI
import EonaCore

/// The plans side by side, stacked when the screen is too narrow for both.
struct SubscriptionPlans: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: EonaSpacing.md) {
                cards
            }
            VStack(spacing: EonaSpacing.md) {
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
        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            HStack(spacing: EonaSpacing.sm) {
                Text(plan.title)
                    .font(.xrHeadline)
                    .foregroundStyle(EonaColor.textPrimary)
                Spacer(minLength: 0)
                if let saving {
                    EonaBadge(text: saving, color: EonaColor.success)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(plan.priceLabel)
                    .font(.xrTitle)
                    .monospacedDigit()
                    .foregroundStyle(EonaColor.textPrimary)
                Text(plan.periodLabel)
                    .font(.xrSubhead)
                    .foregroundStyle(EonaColor.textSecondary)
            }
            Text(plan.perMonthLabel ?? "Chaque mois")
                .font(.xrFootnote)
                .foregroundStyle(EonaColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .xrCard()
        .overlay {
            if saving != nil {
                RoundedRectangle(cornerRadius: EonaRadius.xl)
                    .strokeBorder(EonaColor.accent, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// What membership brings, ticked.
struct MembershipBenefits: View {
    private struct Benefit: Identifiable {
        let icon: EonaIconImage
        let title: String

        var id: String { title }
    }

    private let benefits = [
        Benefit(icon: .symbol(.navigation), title: "Navigation guidée sans limite"),
        Benefit(icon: .asset(.radar), title: "Alertes radars et dangers"),
        Benefit(icon: .symbol(.warning), title: "Signalements sans limite"),
        Benefit(icon: .symbol(.music), title: "Musique au volant"),
        Benefit(icon: .symbol(.user), title: "Photo de profil"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.md) {
            ForEach(benefits) { benefit in
                HStack(spacing: EonaSpacing.md) {
                    EonaGlowTile(icon: benefit.icon)
                    Text(benefit.title)
                        .font(.xrBody)
                        .foregroundStyle(EonaColor.textPrimary)
                    Spacer(minLength: 0)
                    Image(EonaSymbol.check)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(EonaColor.success)
                }
            }
        }
    }
}
