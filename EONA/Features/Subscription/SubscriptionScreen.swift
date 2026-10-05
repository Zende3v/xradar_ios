import SwiftUI
import EonaCore
import EonaData

/// Carte de membre et réserve de trajets. Résumé visible, détail sur demande.
struct SubscriptionScreen: View {
    let services: AppServices
    @State private var registering = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EonaSpacing.xxxl) {
                MembershipPass(account: services.account.account, hasPlus: services.account.hasPlus)
                VStack(alignment: .leading, spacing: EonaSpacing.xxl) {
                    EonaPlusLabel("Avec EONA+", color: EonaPlusStyle.amber)
                    MembershipSummary()
                    MembershipComparison()
                }
                SubscriptionPlans()
                Text("Paiement indisponible actuellement.")
                    .font(.xrCaption)
                    .foregroundStyle(EonaPlusStyle.muted)
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, EonaSpacing.xl)
            .padding(.top, EonaSpacing.md)
            .padding(.bottom, EonaSpacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(EonaPlusStyle.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if services.account.account?.isGuest == true, services.account.account?.isRestricted != true {
                trialAction
            }
        }
        .environment(\.colorScheme, .dark)
        .tint(EonaPlusStyle.amber)
        .navigationTitle("EONA+")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(EonaPlusStyle.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await services.account.reload() }
        .sheet(isPresented: $registering) {
            NavigationStack {
                OnboardingView(account: services.account, converting: true)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { registering = false } } }
            }
        }
        .onChange(of: services.account.account?.isGuest) { _, guest in
            if guest == false { registering = false }
        }
    }

    private var trialAction: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            EonaPlusLabel("7 jours offerts · sans paiement")
            EonaPlusAction(title: "Activer l'essai") { registering = true }
        }
        .frame(maxWidth: 600, alignment: .leading)
        .padding(.horizontal, EonaSpacing.xl)
        .padding(.vertical, EonaSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EonaPlusStyle.canvas)
        .overlay(alignment: .top) { EonaPlusDivider() }
    }
}

/// Passe personnelle : identité au-dessus, compteur comme instrument de bord en dessous.
struct MembershipPass: View {
    let account: Account?
    let hasPlus: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 64
    @ScaledMetric(relativeTo: .title) private var wordmarkSize: CGFloat = 34

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 24, topTrailingRadius: 24)
    }

    private var status: String {
        if account?.isRestricted == true { return "Bloqué" }
        if account?.role == .admin { return "Admin" }
        if hasPlus { return account?.access == .trial ? "Essai EONA+" : "EONA+ actif" }
        return account?.isGuest == true ? "Invité · Gratuit" : "Gratuit"
    }

    private var reserve: String {
        if account?.isRestricted == true { return "—" }
        if hasPlus { return "∞" }
        guard let limits = account?.limits else { return "—" }
        return String(format: "%02d", limits.tripsLeft())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.xl) {
            HStack(alignment: .top, spacing: EonaSpacing.lg) {
                VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                    EonaPlusLabel("Espace membre")
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("EONA").foregroundStyle(EonaPlusStyle.primary)
                        Text("+").foregroundStyle(EonaPlusStyle.amber)
                    }
                    .font(.system(size: wordmarkSize, weight: .semibold))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("EONA Plus")
                    .accessibilityAddTraits(.isHeader)
                    Text(displayName(of: account))
                        .font(.xrBodyStrong)
                        .foregroundStyle(EonaPlusStyle.mineral)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicTypeSize.isAccessibilitySize {
                    MembershipRouteMark()
                        .frame(width: 64, height: 72)
                        .accessibilityHidden(true)
                }
            }

            EonaPlusDivider()

            VStack(alignment: .leading, spacing: EonaSpacing.md) {
                EonaPlusLabel(status, color: hasPlus ? EonaPlusStyle.amber : EonaPlusStyle.secondary)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                        reserveValue
                        reserveCaption
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: EonaSpacing.lg) {
                        reserveValue
                        reserveCaption
                    }
                }
                meter
                if hasPlus, let end = account?.accessEndsAt {
                    EonaPlusLabel("Jusqu'au \(AccountLabels.shortDate(end))")
                } else if !hasPlus, let limits = account?.limits {
                    EonaPlusLabel("\(limits.tripsUsed()) / \(limits.tripsPerDay) utilisés")
                }
            }
        }
        .padding(.leading, EonaSpacing.xxl)
        .padding(.trailing, EonaSpacing.xl)
        .padding(.vertical, EonaSpacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: shape)
        .overlay { shape.strokeBorder(EonaPlusStyle.line, lineWidth: 0.5) }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(EonaPlusStyle.amber)
                .frame(width: 2, height: 42)
                .padding(.top, EonaSpacing.xxl)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .clipShape(shape)
    }

    private var reserveValue: some View {
        Text(reserve)
            .font(.system(size: numberSize, weight: .light, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(EonaPlusStyle.primary)
            .accessibilityLabel(hasPlus ? "Trajets illimités" : reserve == "—" ? "Trajets restants indisponibles" : "\(reserve) trajets restants")
    }

    private var reserveCaption: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.xs) {
            EonaPlusLabel("Trajets")
            Text(hasPlus ? "Sans limite" : "Restants aujourd'hui")
                .font(.xrFootnote)
                .foregroundStyle(EonaPlusStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var meter: some View {
        if hasPlus {
            Rectangle().fill(EonaPlusStyle.amber.opacity(0.65)).frame(height: 2)
        } else {
            HStack(spacing: EonaSpacing.xs) {
                ForEach(0..<4) { index in
                    Rectangle()
                        .fill(index < (account?.limits?.tripsLeft() ?? 0) ? EonaPlusStyle.amber : EonaPlusStyle.line)
                        .frame(height: 2)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// Repère de route gravé ; illustration décorative, jamais donnée de conduite.
private struct MembershipRouteMark: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            ZStack {
                Path { path in
                    for column in 0..<4 {
                        let x = w * CGFloat(column) / 3
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: h))
                    }
                    for row in 0..<5 {
                        let y = h * CGFloat(row) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                    }
                }
                .stroke(EonaPlusStyle.line, lineWidth: 0.5)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.16, y: h * 0.88))
                    path.addLine(to: CGPoint(x: w * 0.16, y: h * 0.62))
                    path.addQuadCurve(to: CGPoint(x: w * 0.42, y: h * 0.42), control: CGPoint(x: w * 0.16, y: h * 0.42))
                    path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.42))
                    path.addQuadCurve(to: CGPoint(x: w * 0.86, y: h * 0.22), control: CGPoint(x: w * 0.86, y: h * 0.42))
                    path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.1))
                }
                .stroke(EonaPlusStyle.amber.opacity(0.65), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
