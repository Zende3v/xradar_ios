import SwiftUI
import EonaCore
import EonaData

/// Même présentation que catégorie EONA+ ; motif du blocage en premier, action fixe en bas.
struct OffersSheet: View {
    let reason: PaywallReason
    let account: Account?
    var store: AccountStore? = nil
    @State private var registering = false
    @Environment(\.dismiss) private var dismiss

    private var currentAccount: Account? { store?.account ?? account }
    private var canTry: Bool { currentAccount?.isGuest == true && store != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EonaSpacing.huge) {
                    header
                    MembershipComparison()
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
                .padding(.top, EonaSpacing.md)
                .padding(.bottom, EonaSpacing.xxxl)
                .frame(maxWidth: .infinity)
            }
            .background(EonaColor.canvas)
            .safeAreaInset(edge: .bottom, spacing: 0) { action }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(EonaSymbol.close) }
                        .accessibilityLabel("Fermer")
                }
            }
        }
        .sheet(isPresented: $registering) {
            if let store {
                NavigationStack {
                    OnboardingView(account: store, converting: true)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { registering = false } } }
                }
            }
        }
        .onChange(of: store?.account?.isGuest) { _, guest in
            if guest == false { registering = false; dismiss() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.xxl) {
            MembershipWordmark(compact: true)
            VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                Text(reason.title(for: currentAccount))
                    .font(.xrTitle)
                    .foregroundStyle(EonaColor.textPrimary)
                Text(reason.message(for: currentAccount))
                    .font(.xrCallout)
                    .foregroundStyle(EonaColor.textSecondary)
            }
            Text(AccountLabels.access(currentAccount, nowMillis: nowMillis()))
                .font(.xrCaption)
                .foregroundStyle(EonaColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var action: some View {
        VStack(spacing: EonaSpacing.sm) {
            if canTry {
                EonaButton(title: "Essayer EONA+ pendant 7 jours", fillWidth: true) { registering = true }
                Text("Sans paiement. Puis retour à l'offre gratuite.")
                    .font(.xrCaption)
                    .foregroundStyle(EonaColor.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                EonaButton(title: "Fermer", variant: .secondary, fillWidth: true) { dismiss() }
            }
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
