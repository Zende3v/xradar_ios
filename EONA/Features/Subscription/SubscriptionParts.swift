import SwiftUI
import EonaCore

/// Tarifs alignés, sans contrôle d'achat.
struct SubscriptionPlans: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(SubscriptionPlan.all) { plan in
                PlanRow(plan: plan)
                if plan.id != SubscriptionPlan.all.last?.id {
                    Rectangle()
                        .fill(EonaColor.separator)
                        .frame(height: 1)
                }
            }
        }
    }
}

private struct PlanRow: View {
    let plan: SubscriptionPlan
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                    details
                    price
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: EonaSpacing.lg) {
                    details
                    Spacer(minLength: EonaSpacing.sm)
                    price
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, EonaSpacing.lg)
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.xs) {
            Text(plan.title)
                .font(.xrBodyStrong)
                .foregroundStyle(EonaColor.textPrimary)
            if let saving = plan.savingLabel {
                Text("\(saving) sur l'année")
                    .font(.xrCaption)
                    .foregroundStyle(EonaColor.textSecondary)
            }
        }
    }

    private var price: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: EonaSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(plan.priceLabel)
                    .font(.xrTitle)
                    .monospacedDigit()
                    .foregroundStyle(EonaColor.textPrimary)
                Text(plan.periodLabel)
                    .font(.xrSubhead)
                    .foregroundStyle(EonaColor.textSecondary)
            }
            if let perMonth = plan.perMonthLabel {
                Text(perMonth)
                    .font(.xrCaption)
                    .foregroundStyle(EonaColor.textTertiary)
            }
        }
    }
}

/// Comparatif partagé entre catégorie EONA+ et fenêtres d'offre.
struct MembershipComparison: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Feature: Identifiable {
        let title: String
        let free: String
        let plus: String
        var id: String { title }
    }
    private let features = [
        Feature(title: "Trajets", free: "4 / jour", plus: "Illimités"),
        Feature(title: "Trajets intelligents", free: "1 / jour", plus: "Illimités"),
        Feature(title: "Guidage, trafic, alertes", free: "Inclus", plus: "Inclus"),
        Feature(title: "Signalements", free: "Inclus", plus: "Inclus"),
        Feature(title: "Apple Music / autres", free: "Inclus", plus: "Inclus"),
        Feature(title: "EONA Taxi", free: "Verrouillé", plus: "Inclus"),
        Feature(title: "EONA Poids lourd", free: "Verrouillé", plus: "Inclus"),
        Feature(title: "Trajets en groupe", free: "Verrouillé", plus: "Inclus"),
        Feature(title: "Thème", free: "Cyan", plus: "11 couleurs"),
        Feature(title: "Feux en direct", free: "Verrouillé", plus: "Inclus"),
    ]

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleRows
            } else {
                columns
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var columns: some View {
        Grid(alignment: .leading, horizontalSpacing: EonaSpacing.md, verticalSpacing: 0) {
            GridRow {
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
                Text("Gratuit")
                    .gridColumnAlignment(.trailing)
                Text("EONA+")
                    .foregroundStyle(EonaColor.accent)
                    .gridColumnAlignment(.trailing)
            }
            .font(.xrCaption)
            .foregroundStyle(EonaColor.textSecondary)
            .padding(.bottom, EonaSpacing.md)

            ForEach(features) { feature in
                separator.gridCellColumns(3)
                GridRow {
                    Text(feature.title)
                        .foregroundStyle(EonaColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(feature.free)
                        .foregroundStyle(EonaColor.textSecondary)
                    Text(feature.plus)
                        .fontWeight(.medium)
                        .foregroundStyle(EonaColor.textPrimary)
                }
                .font(.xrFootnote)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, EonaSpacing.md)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(feature.title). Gratuit : \(feature.free). EONA+ : \(feature.plus).")
            }
        }
    }

    private var accessibleRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(features) { feature in
                separator
                VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                    Text(feature.title)
                        .font(.xrBodyStrong)
                        .foregroundStyle(EonaColor.textPrimary)
                    HStack(alignment: .top, spacing: EonaSpacing.lg) {
                        value("Gratuit", feature.free)
                        value("EONA+", feature.plus)
                    }
                }
                .padding(.vertical, EonaSpacing.lg)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func value(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: EonaSpacing.xs) {
            Text(title)
                .font(.xrCaption)
                .foregroundStyle(EonaColor.textSecondary)
            Text(value)
                .font(.xrBody)
                .foregroundStyle(EonaColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var separator: some View {
        Rectangle()
            .fill(EonaColor.separator)
            .frame(height: 1)
            .gridCellUnsizedAxes(.horizontal)
    }
}
