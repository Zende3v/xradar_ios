import SwiftUI
import EonaCore
import EonaData

/// Offre contextuelle, même rythme et mêmes pastels que page EONA+.
struct OffersSheet: View {
    let reason: PaywallReason
    let account: Account?
    var store: AccountStore? = nil
    @State private var registering = false
    @State private var paymentUnavailable = false
    @State private var benefitPresented = false
    @State private var selectedPlan = SubscriptionPlan.yearly
    @Environment(\.dismiss) private var dismiss

    private var currentAccount: Account? { store?.account ?? account }
    private var canTry: Bool { currentAccount?.isGuest == true && currentAccount?.isRestricted != true && store != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EonaSpacing.xxl) {
                    EonaPlusHero(title: reason.title(for: currentAccount), subtitle: reason.message(for: currentAccount), compact: true, animationsEnabled: !registering && !paymentUnavailable && !benefitPresented)
                    Text(AccountLabels.access(currentAccount, nowMillis: nowMillis()))
                        .font(.footnote)
                        .foregroundStyle(EonaPlusStyle.secondary)
                    SubscriptionPlans(selectedPlan: $selectedPlan)
                    VStack(alignment: .leading, spacing: EonaSpacing.md) {
                        EonaPlusLabel("Vos avantages EONA+")
                            .padding(.leading, EonaSpacing.lg)
                        MembershipSummary(onPresentationChange: { benefitPresented = $0 })
                    }
                    MembershipComparison()
                    Text("Apple Music / autres reste inclus en gratuit.")
                        .font(.footnote)
                        .foregroundStyle(EonaPlusStyle.secondary)
                        .padding(.horizontal, EonaSpacing.lg)
                }
                .frame(maxWidth: 600, alignment: .leading)
                .padding(.horizontal, EonaSpacing.lg)
                .padding(.bottom, EonaSpacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollEdgeEffectHidden(true, for: .all)
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .background(EonaPlusStyle.canvas.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .tint(EonaPlusStyle.lavender)
            .navigationTitle("EONA+")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
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
        .alert("Abonnement EONA+", isPresented: $paymentUnavailable) {
            Button("Fermer", role: .cancel) {}
        } message: {
            Text("Paiement indisponible actuellement. Aucun achat effectué.")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            if canTry {
                EonaPlusAction(title: "Essayer 7 jours gratuits") { registering = true }
            } else if currentAccount != nil && currentAccount?.isGuest != true && currentAccount?.isRestricted != true && currentAccount?.hasPlus() != true {
                Text("Paiement indisponible actuellement.")
                    .font(.caption)
                    .foregroundStyle(EonaPlusStyle.secondary)
                EonaPlusAction(title: "S'abonner pour \(selectedPlan.priceLabel) \(selectedPlan.periodLabel)") {
                    paymentUnavailable = true
                }
            } else {
                EonaPlusAction(title: "Fermer", symbol: "xmark") { dismiss() }
            }
        }
        .frame(maxWidth: 600, alignment: .leading)
        .padding(.horizontal, EonaSpacing.lg)
        .padding(.top, EonaSpacing.md)
        .padding(.bottom, EonaSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
