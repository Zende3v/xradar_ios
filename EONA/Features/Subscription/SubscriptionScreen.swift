import SwiftUI
import EonaCore
import EonaData

/// « EONA + » : l'offre membre. Statut du compte ; EONA + actif : son détail ; sinon les limites
/// du jour et les formules. Pas encore de paiement.
struct SubscriptionScreen: View {
    let services: AppServices

    var body: some View {
        let account = services.account.account
        Form {
            Section {
                hero(account)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            if let account, account.isSubscriber {
                Section("Ton EONA +") {
                    LabeledContent("Formule", value: account.role == .admin ? "Administrateur" : "Membre")
                    LabeledContent("État", value: "Actif")
                    LabeledContent("Échéance", value: account.accessEndsAt == nil ? "Sans échéance" : AccountLabels.shortDate(account.accessEndsAt))
                }
                Section("Inclus") {
                    MembershipBenefits()
                        .padding(.vertical, EonaSpacing.xs)
                }
            } else {
                if let limits = account?.limits, account?.isRestricted == false {
                    Section("Aujourd'hui") {
                        LabeledContent("Signalements", value: "\(limits.reportsUsed()) / \(limits.reportsPerDay)")
                        LabeledContent("Trajets", value: "\(limits.tripsUsed()) / \(limits.tripsPerDay)")
                    }
                }
                Section("Inclus") {
                    MembershipBenefits()
                        .padding(.vertical, EonaSpacing.xs)
                }
                Section {
                    SubscriptionPlans()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                } header: {
                    Text("Formules")
                } footer: {
                    Text("Paiement dans l'app bientôt disponible.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(EonaColor.canvas)
        .navigationTitle("EONA +")
        .navigationBarTitleDisplayMode(.inline)
        // Days and counts move on their own: read them fresh.
        .task { await services.account.reload() }
    }

    /// Couronne, nom, promesse, statut du compte.
    private func hero(_ account: Account?) -> some View {
        VStack(spacing: EonaSpacing.md) {
            EonaGlowTile(icon: .symbol(.crown), size: 72, iconSize: 32, radius: EonaRadius.xxl)
            VStack(spacing: EonaSpacing.xs) {
                Text("EONA +")
                    .font(.xrTitleLarge)
                    .foregroundStyle(EonaColor.textPrimary)
                Text("Toute la route, sans limite.")
                    .font(.xrCallout)
                    .foregroundStyle(EonaColor.textSecondary)
            }
            EonaBadge(text: AccountLabels.access(account, nowMillis: nowMillis()), glow: true)
            Text(Self.status(of: account))
                .font(.xrFootnote)
                .foregroundStyle(EonaColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, EonaSpacing.md)
    }

    private static func status(of account: Account?) -> String {
        guard let account else { return "Connecte-toi pour voir ton statut." }
        if account.role == .admin { return "Accès complet." }
        if account.isRestricted {
            let ended = account.role == .client ? "EONA + terminé" : "Essai terminé"
            return "\(ended). La carte reste disponible."
        }
        if account.role == .client { return "Tout est inclus, sans limite." }
        let perDay = account.limits.map { " · \($0.reportsPerDay) signalements et \($0.tripsPerDay) trajets par jour" } ?? ""
        return "Essai jusqu'au \(AccountLabels.shortDate(account.accessEndsAt))\(perDay)."
    }
}
