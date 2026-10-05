import SwiftUI
import EonaCore

private struct MembershipBenefit: Identifiable, Sendable {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let free: String
    let plus: String
    var id: String { title }

    static let all = [
        MembershipBenefit(title: "Trajets illimités", detail: "Aucune limite quotidienne", symbol: "arrow.turn.up.right", color: EonaPlusStyle.lavender, free: "4 / jour", plus: "Illimités"),
        MembershipBenefit(title: "Trajets intelligents", detail: "1 / jour en gratuit", symbol: "sparkles", color: EonaPlusStyle.pink, free: "1 / jour", plus: "Illimités"),
        MembershipBenefit(title: "EONA Taxi", detail: "Voies Taxi autorisées", symbol: "car.side.fill", color: EonaPlusStyle.peach, free: "Verrouillé", plus: "Inclus"),
        MembershipBenefit(title: "EONA Poids lourd", detail: "Curseur dédié", symbol: "truck.box.fill", color: EonaPlusStyle.sky, free: "Verrouillé", plus: "Inclus"),
        MembershipBenefit(title: "Trajets en groupe", detail: "Rouler ensemble", symbol: "person.2.fill", color: EonaPlusStyle.mint, free: "Verrouillé", plus: "Inclus"),
        MembershipBenefit(title: "Thème", detail: "11 couleurs", symbol: "paintpalette.fill", color: EonaPlusStyle.pink, free: "Cyan", plus: "11 couleurs"),
        MembershipBenefit(title: "Feux en direct", detail: "Timer des feux", symbol: "trafficlight.fill", color: EonaPlusStyle.peach, free: "Verrouillé", plus: "Inclus"),
    ]
}

/// Avantages visibles ; chaque ligne ouvre détail d'offre, sans activer fonctionnalité.
struct MembershipSummary: View {
    @State private var selectedBenefit: MembershipBenefit?
    private let onPresentationChange: (Bool) -> Void

    init(onPresentationChange: @escaping (Bool) -> Void = { _ in }) {
        self.onPresentationChange = onPresentationChange
    }

    var body: some View {
        EonaPlusGroup {
            VStack(spacing: 0) {
                ForEach(MembershipBenefit.all) { benefit in
                    BenefitRow(benefit: benefit) { selectedBenefit = benefit }
                    if benefit.id != MembershipBenefit.all.last?.id {
                        EonaPlusDivider().padding(.leading, 68)
                    }
                }
            }
        }
        .sheet(item: $selectedBenefit) { benefit in
            MembershipBenefitSheet(benefit: benefit)
        }
        .onChange(of: selectedBenefit?.id) { _, id in
            onPresentationChange(id != nil)
        }
    }
}

private struct BenefitRow: View {
    let benefit: MembershipBenefit
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: EonaSpacing.md) {
                Image(systemName: benefit.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(benefit.color)
                    .frame(width: 40, height: 40)
                    .background(benefit.color.opacity(0.14), in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: EonaSpacing.xs) {
                    Text(benefit.title)
                        .font(.xrBodyStrong)
                        .foregroundStyle(EonaPlusStyle.primary)
                    Text(benefit.detail)
                        .font(.xrFootnote)
                        .foregroundStyle(EonaPlusStyle.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EonaPlusStyle.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, EonaSpacing.lg)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(benefit.title)
        .accessibilityValue(benefit.detail)
        .accessibilityHint("Afficher le détail de l'offre")
    }
}

private struct MembershipBenefitSheet: View {
    let benefit: MembershipBenefit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EonaSpacing.xxl) {
                    Image(systemName: benefit.symbol)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(benefit.color)
                        .frame(width: 76, height: 76)
                        .background(benefit.color.opacity(0.14), in: .rect(cornerRadius: 24))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                        Text(benefit.title)
                            .font(.xrTitleLarge)
                            .foregroundStyle(EonaPlusStyle.primary)
                            .accessibilityAddTraits(.isHeader)
                        Text(benefit.detail)
                            .font(.xrBody)
                            .foregroundStyle(EonaPlusStyle.secondary)
                    }
                    EonaPlusGroup {
                        VStack(spacing: 0) {
                            detailValue("Gratuit", benefit.free, color: EonaPlusStyle.secondary)
                            EonaPlusDivider().padding(.horizontal, EonaSpacing.lg)
                            detailValue("EONA+", benefit.plus, color: benefit.color)
                        }
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(EonaSpacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(EonaPlusStyle.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(benefit.color)
                }
            }
            .toolbarBackground(EonaPlusStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .environment(\.colorScheme, .dark)
        .presentationBackground(EonaPlusStyle.canvas)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func detailValue(_ title: String, _ value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: EonaSpacing.lg) {
            Text(title).foregroundStyle(EonaPlusStyle.secondary)
            Spacer(minLength: EonaSpacing.sm)
            Text(value).foregroundStyle(color).multilineTextAlignment(.trailing)
        }
        .font(.xrBodyStrong)
        .fixedSize(horizontal: false, vertical: true)
        .padding(EonaSpacing.lg)
        .accessibilityElement(children: .combine)
    }
}

/// Deux formules indicatives. Sélection partagée avec page et fenêtre d'offre.
struct SubscriptionPlans: View {
    @Binding var selectedPlan: SubscriptionPlan
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(selectedPlan: Binding<SubscriptionPlan>) {
        self._selectedPlan = selectedPlan
    }

    var body: some View {
        EonaPlusGroup {
            VStack(spacing: 0) {
                planRow(.yearly)
                EonaPlusDivider().padding(.leading, 50)
                planRow(.monthly)
            }
        }
    }

    private func planRow(_ plan: SubscriptionPlan) -> some View {
        let selected = plan.id == selectedPlan.id
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                selectedPlan = plan
            }
        } label: {
            HStack(alignment: .top, spacing: EonaSpacing.md) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(selected ? EonaPlusStyle.lavender : EonaPlusStyle.muted)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: EonaSpacing.xs) {
                    if dynamicTypeSize.isAccessibilitySize {
                        planTitle(plan)
                        planPrice(plan)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: EonaSpacing.md) {
                            planTitle(plan)
                            Spacer(minLength: EonaSpacing.xs)
                            planPrice(plan)
                        }
                    }
                    if let perMonth = plan.perMonthLabel {
                        Text(perMonth)
                            .font(.xrFootnote)
                            .foregroundStyle(EonaPlusStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(EonaSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plan.title), \(plan.priceLabel)\(plan.periodLabel). \(plan.perMonthLabel ?? "") \(plan.savingLabel ?? "")")
        .accessibilityValue(selected ? "Sélectionné" : "Non sélectionné")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Afficher cette formule")
    }

    private func planTitle(_ plan: SubscriptionPlan) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: EonaSpacing.sm) {
            Text(plan.title)
                .font(.xrBodyStrong)
                .foregroundStyle(EonaPlusStyle.primary)
            if let saving = plan.savingLabel {
                Text(saving)
                    .font(.xrCaption)
                    .foregroundStyle(EonaPlusStyle.mint)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func planPrice(_ plan: SubscriptionPlan) -> some View {
        Text("\(plan.priceLabel)\(plan.periodLabel)")
            .font(.xrSubhead.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(EonaPlusStyle.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Comparatif complet, replié au lancement. Fonctions visibles dans résumé permanent.
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
        EonaPlusGroup {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        expanded.toggle()
                    }
                } label: {
                    HStack(spacing: EonaSpacing.md) {
                        Text("Comparer les offres")
                            .font(.xrBodyStrong)
                        Spacer(minLength: EonaSpacing.md)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(EonaPlusStyle.lavender)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(EonaPlusStyle.primary)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .padding(EonaSpacing.lg)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Comparer les offres")
                .accessibilityValue(expanded ? "Déplié" : "Replié")
                .accessibilityHint(expanded ? "Masquer le comparatif" : "Afficher le comparatif")

                if expanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(features) { feature in
                            EonaPlusDivider().padding(.horizontal, EonaSpacing.lg)
                            featureRow(feature)
                        }
                    }
                }
            }
        }
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
        .padding(EonaSpacing.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(feature.title). Gratuit : \(feature.free). EONA+ : \(feature.plus).")
    }

    private func value(_ title: String, _ value: String, plus: Bool) -> some View {
        VStack(alignment: .leading, spacing: EonaSpacing.xs) {
            Text(title)
                .font(.xrCaption)
                .foregroundStyle(plus ? EonaPlusStyle.lavender : EonaPlusStyle.secondary)
            Text(value)
                .font(.xrSubhead)
                .foregroundStyle(plus ? EonaPlusStyle.primary : EonaPlusStyle.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
