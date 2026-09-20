import SwiftUI
import EonaCore

/// The offers, over a blocked action: why it is blocked, the plans, what membership brings.
/// No payment yet: the plans are shown, not sold.
struct OffersSheet: View {
    let reason: PaywallReason
    let account: Account?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: EonaSpacing.xxl) {
                    header
                    SubscriptionPlans()
                    MembershipBenefits()
                        .xrCard()
                    VStack(spacing: EonaSpacing.md) {
                        Text("Le paiement dans l'app arrive bientôt.")
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
