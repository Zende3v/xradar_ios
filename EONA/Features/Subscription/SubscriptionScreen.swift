import SwiftUI
import EonaCore
import EonaData

/// Offre, statut, comparaison et prix. Essai réel ; paiement encore indisponible.
struct SubscriptionScreen: View {
    let services: AppServices
    @State private var registering = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EonaSpacing.xl) {
                hero
                status
                if let limits = services.account.account?.limits, !services.account.hasPlus {
                    HStack {
                        Text("Trajets aujourd'hui")
                        Spacer()
                        Text("\(limits.tripsUsed()) / \(limits.tripsPerDay)").monospacedDigit()
                    }
                    .font(.xrBody)
                    .foregroundStyle(EonaColor.textPrimary)
                    .xrCard()
                }
                MembershipComparison()
                if services.account.account?.isGuest == true {
                    VStack(alignment: .leading, spacing: EonaSpacing.md) {
                        Text("Sept jours offerts").font(.xrTitle)
                        Text("Crée ton compte. Aucun paiement. Puis accès gratuit automatique, compte conservé.")
                            .font(.xrFootnote)
                            .foregroundStyle(EonaColor.textSecondary)
                        EonaButton(title: "Créer mon compte", fillWidth: true) { registering = true }
                    }
                    .foregroundStyle(EonaColor.textPrimary)
                    .xrCard()
                }
                VStack(alignment: .leading, spacing: EonaSpacing.md) {
                    Text("Formules EONA+").font(.xrHeadline)
                    SubscriptionPlans()
                    Text("Paiement dans l'app bientôt disponible.")
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textTertiary)
                }
            }
            .padding(EonaSpacing.lg)
        }
        .background(EonaColor.canvas)
        .navigationTitle("EONA+")
        .navigationBarTitleDisplayMode(.inline)
        // Days and counts move on their own: read them fresh.
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

    /// Couronne, nom, promesse, statut du compte.
    private var hero: some View {
        VStack(spacing: EonaSpacing.md) {
            EonaGlowTile(icon: .symbol(.crown), size: 72, iconSize: 32, radius: EonaRadius.xxl)
            VStack(spacing: EonaSpacing.xs) {
                Text("EONA+")
                    .font(.xrTitleLarge)
                    .foregroundStyle(EonaColor.textPrimary)
                Text("Plus de liberté sur chaque trajet.")
                    .font(.xrCallout)
                    .foregroundStyle(EonaColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, EonaSpacing.md)
    }

    private var status: some View {
        let account = services.account.account
        return VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            EonaBadge(text: AccountLabels.access(account, nowMillis: nowMillis()), glow: services.account.hasPlus)
            Text(services.account.hasPlus ? "Tous tes trajets, sans limite quotidienne." : "Gratuit, sans limite de temps. Quatre trajets chaque jour.")
                .font(.xrBody)
                .foregroundStyle(EonaColor.textPrimary)
            if services.account.hasPlus, let end = account?.accessEndsAt {
                Text("\(account?.access == .trial ? "Essai offert" : "Accès actif") jusqu'au \(AccountLabels.shortDate(end)).")
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .xrCard()
    }
}
