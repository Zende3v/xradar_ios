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

/// Comparatif partagé entre catégorie EONA+ et fenêtres d'offre.
struct MembershipComparison: View {
    private struct Feature: Identifiable {
        let title: String
        let free: String
        let plus: String
        var id: String { title }
    }
    private let features = [
        Feature(title: "Trajets", free: "4 / jour", plus: "Illimités"),
        Feature(title: "Guidage, trafic, alertes", free: "Inclus", plus: "Inclus"),
        Feature(title: "Signalements", free: "Inclus", plus: "Inclus"),
        Feature(title: "Mini-player musique", free: "Inclus", plus: "Inclus"),
        Feature(title: "Profil Taxi", free: "Verrouillé", plus: "Inclus"),
        Feature(title: "Curseur Camion", free: "Verrouillé", plus: "Inclus"),
        Feature(title: "Trajets en groupe", free: "Verrouillé", plus: "Inclus"),
        Feature(title: "Couleurs de l'app", free: "Cyan", plus: "11 couleurs"),
        Feature(title: "Feux en direct", free: "Verrouillé", plus: "À venir"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.md) {
            Text("Choisis ton offre")
                .font(.xrHeadline)
                .foregroundStyle(EonaColor.textPrimary)
            Grid(alignment: .leading, horizontalSpacing: EonaSpacing.sm, verticalSpacing: EonaSpacing.md) {
                GridRow {
                    Text("Chaque jour")
                    Text("Gratuit")
                    Text("EONA+").foregroundStyle(EonaColor.accent)
                }
                .font(.xrFootnote.weight(.semibold))
                .foregroundStyle(EonaColor.textSecondary)
                ForEach(features) { feature in
                    GridRow {
                        Text(feature.title).frame(maxWidth: .infinity, alignment: .leading)
                        Text(feature.free).foregroundStyle(EonaColor.textSecondary)
                        Text(feature.plus).foregroundStyle(EonaColor.accent)
                    }
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textPrimary)
                }
            }
            Text("Feux en direct : fonction en préparation. Aucun compte à rebours disponible actuellement.")
                .font(.xrCaption)
                .foregroundStyle(EonaColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .xrCard()
    }
}
