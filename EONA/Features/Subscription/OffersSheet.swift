import SwiftUI
import EonaCore
import EonaData

/// The offers, over a blocked action: why it is blocked, the plans, what membership brings.
/// No payment yet: the plans are shown, not sold.
struct OffersSheet: View {
    let reason: PaywallReason
    let account: Account?
    var store: AccountStore? = nil
    @State private var registering = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: EonaSpacing.xxl) {
                    header
                    MembershipComparison()
                    if account?.isGuest == true, store != nil {
                        EonaButton(title: "Activer sept jours offerts", fillWidth: true) { registering = true }
                        Text("Crée ton compte. Historique conservé. Puis accès gratuit automatique.")
                            .font(.xrFootnote)
                            .foregroundStyle(EonaColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    SubscriptionPlans()
                    VStack(spacing: EonaSpacing.md) {
                        Text("Paiement dans l'app bientôt disponible.")
                            .font(.xrFootnote)
                            .foregroundStyle(EonaColor.textTertiary)
                            .multilineTextAlignment(.center)
                        EonaButton(title: "Plus tard", variant: .secondary, fillWidth: true) {
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, EonaSpacing.lg)
                .padding(.bottom, EonaSpacing.xxl)
            }
            .background(EonaColor.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(EonaSymbol.close)
                    }
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
        VStack(spacing: EonaSpacing.md) {
            EonaGlowTile(icon: .symbol(.crown), size: 80, iconSize: 36, radius: EonaRadius.xxl)
            Text(reason.title(for: account))
                .font(.xrTitle)
                .foregroundStyle(EonaColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(reason.message(for: account))
                .font(.xrCallout)
                .foregroundStyle(EonaColor.textSecondary)
                .multilineTextAlignment(.center)
            EonaBadge(text: AccountLabels.access(account, nowMillis: nowMillis()), glow: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, EonaSpacing.sm)
    }
}
