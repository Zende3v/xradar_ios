import SwiftUI
import XRadarCore

/// The offers, over a blocked action: why it is blocked, the plans, what membership brings.
/// No payment yet: the plans are shown, not sold.
struct OffersSheet: View {
    let reason: PaywallReason
    let account: Account?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: XRadarSpacing.xxl) {
                    header
                    SubscriptionPlans()
                    MembershipBenefits()
                        .xrCard()
                    VStack(spacing: XRadarSpacing.md) {
                        Text("Le paiement dans l'app arrive bientôt.")
                            .font(.xrFootnote)
                            .foregroundStyle(XRadarColor.textTertiary)
                            .multilineTextAlignment(.center)
                        XRadarButton(title: "Plus tard", variant: .secondary, fillWidth: true) {
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, XRadarSpacing.lg)
                .padding(.bottom, XRadarSpacing.xxl)
            }
            .background(XRadarColor.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(XRadarSymbol.close)
                    }
                    .accessibilityLabel("Fermer")
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: XRadarSpacing.md) {
            XRadarGlowIcon(icon: .symbol(.crown), tint: XRadarColor.warning, size: 34, glowRadius: 8)
                .frame(width: 80, height: 80)
                .background(XRadarColor.warning.opacity(0.14), in: .rect(cornerRadius: XRadarRadius.xxl))
            Text(reason.title(for: account))
                .font(.xrTitle)
                .foregroundStyle(XRadarColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(reason.message(for: account))
                .font(.xrCallout)
                .foregroundStyle(XRadarColor.textSecondary)
                .multilineTextAlignment(.center)
            XRadarBadge(text: AccountLabels.access(account, nowMillis: nowMillis()), color: accessColor(account))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, XRadarSpacing.sm)
    }
}
