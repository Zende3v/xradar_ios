import SwiftUI
import EonaCore
import EonaData

/// Offre lisible : identité, accès actuel, comparatif, tarifs. Action invité fixe en bas.
struct SubscriptionScreen: View {
    let services: AppServices
    @State private var registering = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EonaSpacing.huge) {
                VStack(alignment: .leading, spacing: EonaSpacing.md) {
                    MembershipWordmark()
                    Text("Trajets illimités.")
                        .font(.xrTitleLarge)
                        .foregroundStyle(EonaColor.textSecondary)
                }
                .padding(.top, EonaSpacing.xl)

                status

                VStack(alignment: .leading, spacing: EonaSpacing.lg) {
                    MembershipSectionTitle(title: "Fonctionnalités")
                    MembershipComparison()
                }

                VStack(alignment: .leading, spacing: EonaSpacing.lg) {
                    MembershipSectionTitle(title: "Abonnement")
                    SubscriptionPlans()
                    Text("Paiement dans l'app bientôt disponible.")
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textTertiary)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, EonaSpacing.xxl)
            .padding(.bottom, EonaSpacing.xxxl)
            .frame(maxWidth: .infinity)
        }
        .background(EonaColor.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if services.account.account?.isGuest == true {
                trialAction
            }
        }
        .navigationTitle("EONA+")
        .navigationBarTitleDisplayMode(.inline)
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

    private var status: some View {
        let account = services.account.account
        return VStack(alignment: .leading, spacing: EonaSpacing.md) {
            Rectangle().fill(EonaColor.separator).frame(height: 0.5)
            HStack(alignment: .top, spacing: EonaSpacing.lg) {
                VStack(alignment: .leading, spacing: EonaSpacing.xs) {
                    Text("Ton accès")
                        .font(.xrCaption)
                        .foregroundStyle(EonaColor.textTertiary)
                    Text(AccountLabels.access(account, nowMillis: nowMillis()))
                        .font(.xrBodyStrong)
                        .foregroundStyle(EonaColor.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: EonaSpacing.xs) {
                    if !services.account.hasPlus, let limits = account?.limits {
                        Text("\(limits.tripsUsed()) / \(limits.tripsPerDay)")
                            .font(.xrNumeric)
                            .foregroundStyle(EonaColor.textPrimary)
                        Text("Trajets aujourd'hui")
                            .font(.xrCaption)
                            .foregroundStyle(EonaColor.textTertiary)
                    } else if services.account.hasPlus, let end = account?.accessEndsAt {
                        Text(AccountLabels.shortDate(end))
                            .font(.xrNumeric)
                            .foregroundStyle(EonaColor.textPrimary)
                        Text(account?.access == .trial ? "Fin de l'essai" : "Fin de l'accès")
                            .font(.xrCaption)
                            .foregroundStyle(EonaColor.textTertiary)
                    }
                }
                .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, EonaSpacing.xs)
            Rectangle().fill(EonaColor.separator).frame(height: 0.5)
        }
    }

    private var trialAction: some View {
        VStack(spacing: EonaSpacing.sm) {
            EonaButton(title: "Essayer EONA+ pendant 7 jours", fillWidth: true) { registering = true }
            Text("Sans paiement. Puis retour à l'offre gratuite.")
                .font(.xrCaption)
                .foregroundStyle(EonaColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, EonaSpacing.xxl)
        .padding(.vertical, EonaSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(EonaColor.canvas)
        .overlay(alignment: .top) {
            Rectangle().fill(EonaColor.separator).frame(height: 0.5)
        }
    }
}

/// Signature typographique commune aux offres. Accent réservé au signe plus.
struct MembershipWordmark: View {
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 52
    private let compact: Bool

    init(compact: Bool = false) {
        self.compact = compact
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("EONA").tracking(-1.5).foregroundStyle(EonaColor.textPrimary)
            Text("+").tracking(-1.5).foregroundStyle(EonaColor.accent)
        }
        .font(.system(size: compact ? titleSize * 0.75 : titleSize, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("EONA Plus")
        .accessibilityAddTraits(.isHeader)
    }
}

struct MembershipSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.xrCaption)
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(EonaColor.textTertiary)
            .accessibilityAddTraits(.isHeader)
    }
}
