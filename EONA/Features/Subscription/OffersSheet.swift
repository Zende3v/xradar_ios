import SwiftUI
import EonaCore
import EonaData

/// Offre contextuelle : motif court, résumé, comparaison facultative, action en verre.
struct OffersSheet: View {
    let reason: PaywallReason
    let account: Account?
    var store: AccountStore? = nil
    @State private var registering = false
    @Environment(\.dismiss) private var dismiss

    private var currentAccount: Account? { store?.account ?? account }
    private var canTry: Bool { currentAccount?.isGuest == true && currentAccount?.isRestricted != true && store != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EonaSpacing.xxxl) {
                    header
                    MembershipSummary()
                    MembershipComparison()
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
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .environment(\.colorScheme, .dark)
            .tint(EonaPlusStyle.amber)
            .toolbarBackground(EonaPlusStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(EonaSymbol.close) }
                        .foregroundStyle(EonaPlusStyle.mineral)
                        .accessibilityLabel("Fermer")
                }
            }
        }
        .presentationBackground(EonaPlusStyle.canvas)
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
        VStack(alignment: .leading, spacing: EonaSpacing.lg) {
            HStack(spacing: EonaSpacing.md) {
                EonaPlusLabel("EONA+", color: EonaPlusStyle.amber)
                Rectangle().fill(EonaPlusStyle.line).frame(height: 0.5)
            }
            Text(reason.title(for: currentAccount))
                .font(.xrTitleLarge)
                .foregroundStyle(EonaPlusStyle.primary)
                .accessibilityAddTraits(.isHeader)
            Text(reason.message(for: currentAccount))
                .font(.xrSubhead)
                .foregroundStyle(EonaPlusStyle.secondary)
            EonaPlusLabel(AccountLabels.access(currentAccount, nowMillis: nowMillis()))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            if canTry {
                EonaPlusLabel("7 jours offerts · sans paiement")
                EonaPlusAction(title: "Activer l'essai") { registering = true }
            } else {
                EonaPlusAction(title: "Fermer", symbol: "xmark") { dismiss() }
            }
        }
        .frame(maxWidth: 600, alignment: .leading)
        .padding(.horizontal, EonaSpacing.xl)
        .padding(.vertical, EonaSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EonaPlusStyle.canvas)
        .overlay(alignment: .top) { EonaPlusDivider() }
    }
}
