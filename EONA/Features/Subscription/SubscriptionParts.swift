import SwiftUI
import EonaCore

/// Résumé permanent. Trois registres, aucune carte répétée.
struct MembershipSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SummaryRow(number: "01", category: "Trajets", title: "Trajets illimités", detail: "Trajets intelligents")
            EonaPlusDivider()
            SummaryRow(number: "02", category: "Véhicules", title: "EONA Taxi", detail: "EONA Poids lourd")
            EonaPlusDivider()
            SummaryRow(number: "03", category: "À bord", title: "Trajets en groupe", detail: "Thème · Feux en direct")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SummaryRow: View {
    let number: String
    let category: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: EonaSpacing.xl) {
            Text(number)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(EonaPlusStyle.amber)
                .fixedSize()
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                EonaPlusLabel(category)
                Text(title)
                    .font(.xrBodyStrong)
                    .foregroundStyle(EonaPlusStyle.primary)
                Text(detail)
                    .font(.xrFootnote)
                    .foregroundStyle(EonaPlusStyle.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, EonaSpacing.lg)
        .accessibilityElement(children: .combine)
    }
}

/// Sélection indicative. Aucun achat ni engagement.
struct SubscriptionPlans: View {
    @State private var selectedPlan = SubscriptionPlan.monthly
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var priceSize: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.xxl) {
            HStack(alignment: .top, spacing: EonaSpacing.xxl) {
                ForEach(SubscriptionPlan.all) { plan in
                    planTab(plan)
                }
            }

            VStack(alignment: .leading, spacing: EonaSpacing.md) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: EonaSpacing.xs) {
                            amount
                            period
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: EonaSpacing.sm) {
                            amount
                            period
                        }
                    }
                }
                .accessibilityElement(children: .combine)

                if let perMonth = selectedPlan.perMonthLabel {
                    Text(perMonth)
                        .font(.xrFootnote)
                        .foregroundStyle(EonaPlusStyle.secondary)
                }
                if let saving = selectedPlan.savingLabel {
                    EonaPlusLabel("\(saving) sur l'année", color: EonaPlusStyle.amber)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func planTab(_ plan: SubscriptionPlan) -> some View {
        let selected = plan.id == selectedPlan.id
        return Button {
            selectedPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                EonaPlusLabel(plan.title, color: selected ? EonaPlusStyle.amber : EonaPlusStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                Rectangle()
                    .fill(selected ? EonaPlusStyle.amber : EonaPlusStyle.line)
                    .frame(height: selected ? 1 : 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(plan.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var amount: some View {
        Text(selectedPlan.priceLabel)
            .font(.system(size: priceSize, weight: .light))
            .monospacedDigit()
            .foregroundStyle(EonaPlusStyle.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
    }

    private var period: some View {
        Text(selectedPlan.periodLabel)
            .font(.xrSubhead)
            .foregroundStyle(EonaPlusStyle.secondary)
    }
}

/// Comparatif complet, fermé au lancement. Valeurs alignées gauche, sans grille.
struct MembershipComparison: View {
    @State private var expanded = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        VStack(alignment: .leading, spacing: 0) {
            EonaPlusDivider()
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: EonaSpacing.md) {
                    Text("Comparer les offres")
                        .font(.xrBodyStrong)
                    Spacer(minLength: EonaSpacing.md)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(EonaPlusStyle.amber)
                }
                .foregroundStyle(EonaPlusStyle.primary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, EonaSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comparer les offres")
            .accessibilityValue(expanded ? "Déplié" : "Replié")
            .accessibilityHint(expanded ? "Masquer le comparatif" : "Afficher le comparatif")

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(features) { feature in
                        EonaPlusDivider()
                        featureRow(feature)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func featureRow(_ feature: Feature) -> some View {
        VStack(alignment: .leading, spacing: EonaSpacing.md) {
            Text(feature.title)
                .font(.xrBodyStrong)
                .foregroundStyle(EonaPlusStyle.primary)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: EonaSpacing.md) {
                        value("Gratuit", feature.free, plus: false)
                        value("EONA+", feature.plus, plus: true)
                    }
                } else {
                    HStack(alignment: .top, spacing: EonaSpacing.xxl) {
                        value("Gratuit", feature.free, plus: false)
                        value("EONA+", feature.plus, plus: true)
                    }
                }
            }
        }
        .padding(.vertical, EonaSpacing.xl)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(feature.title). Gratuit : \(feature.free). EONA+ : \(feature.plus).")
    }

    private func value(_ title: String, _ value: String, plus: Bool) -> some View {
        VStack(alignment: .leading, spacing: EonaSpacing.xs) {
            EonaPlusLabel(title, color: plus ? EonaPlusStyle.amber : EonaPlusStyle.secondary)
            Text(value)
                .font(.xrSubhead)
                .foregroundStyle(plus ? EonaPlusStyle.primary : EonaPlusStyle.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
