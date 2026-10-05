import SwiftUI
import EonaCore
import EonaData

/// Présentation EONA+ : radar animé, offres compactes et fonctions illustrées.
struct SubscriptionScreen: View {
    let services: AppServices
    @State private var registering = false
    @State private var paymentUnavailable = false
    @State private var benefitPresented = false
    @State private var showingProfile = false
    @State private var selectedPlan = SubscriptionPlan.yearly

    private var canTry: Bool {
        services.account.account?.isGuest == true && services.account.account?.isRestricted != true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EonaSpacing.xxl) {
                EonaPlusHero(subtitle: "Allez au-delà des limites et débloquez davantage d'exclusivités.", animationsEnabled: !registering && !paymentUnavailable && !benefitPresented)
                if services.account.account != nil {
                    Text(AccountLabels.access(services.account.account, nowMillis: nowMillis()))
                        .font(.footnote)
                        .foregroundStyle(EonaPlusStyle.secondary)
                }
                SubscriptionPlans(selectedPlan: $selectedPlan)
                VStack(alignment: .leading, spacing: EonaSpacing.md) {
                    EonaPlusLabel("Ce qui est inclus")
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
        .background(EonaPlusStyle.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if services.account.account != nil && services.account.account?.isRestricted != true {
                footer
            }
        }
        .environment(\.colorScheme, .dark)
        .tint(EonaPlusStyle.lavender)
        .navigationTitle("EONA+")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(EonaPlusStyle.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await services.account.reload() }
        .navigationDestination(isPresented: $showingProfile) {
            ProfileScreen(services: services)
        }
        .sheet(isPresented: $registering) {
            NavigationStack {
                OnboardingView(account: services.account, converting: true)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { registering = false } } }
            }
        }
        .onChange(of: services.account.account?.isGuest) { _, guest in
            if guest == false { registering = false }
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
            } else if services.account.hasPlus {
                EonaPlusAction(title: "Mon compte EONA+", symbol: "checkmark") { showingProfile = true }
            } else {
                Text("Paiement indisponible actuellement.")
                    .font(.caption)
                    .foregroundStyle(EonaPlusStyle.secondary)
                EonaPlusAction(title: "S'abonner pour \(selectedPlan.priceLabel) \(selectedPlan.periodLabel)") {
                    paymentUnavailable = true
                }
            }
        }
        .frame(maxWidth: 600, alignment: .leading)
        .padding(.horizontal, EonaSpacing.lg)
        .padding(.top, EonaSpacing.md)
        .padding(.bottom, EonaSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EonaPlusStyle.canvas, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) { EonaPlusDivider() }
    }
}
