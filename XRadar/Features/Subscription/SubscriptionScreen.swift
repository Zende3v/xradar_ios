import SwiftUI
import XRadarCore
import XRadarData

/// "Abonnement": where the account stands; a running subscription's details, or else today's
/// limits and the plans. No payment yet.
struct SubscriptionScreen: View {
    let services: AppServices

    var body: some View {
        let account = services.account.account
        Form {
            Section {
                VStack(alignment: .leading, spacing: XRadarSpacing.sm) {
                    XRadarBadge(text: AccountLabels.access(account, nowMillis: nowMillis()), color: accessColor(account))
                    Text(Self.status(of: account))
                        .font(.xrSubhead)
                        .foregroundStyle(XRadarColor.textSecondary)
                }
                .padding(.vertical, XRadarSpacing.xs)
            } header: {
                Text("Statut")
            }

            if let account, account.isSubscriber {
                Section("Ton abonnement") {
                    LabeledContent("Formule", value: account.role == .admin ? "Administrateur" : "Membre")
                    LabeledContent("État", value: "Actif")
                    LabeledContent("Échéance", value: account.accessEndsAt == nil ? "Sans échéance" : AccountLabels.shortDate(account.accessEndsAt))
                }
                Section("Inclus") {
                    MembershipBenefits()
                        .padding(.vertical, XRadarSpacing.xs)
                }
            } else {
                if let limits = account?.limits, account?.isRestricted == false {
                    Section("Aujourd'hui") {
                        LabeledContent("Signalements", value: "\(limits.reportsUsed()) / \(limits.reportsPerDay)")
                        LabeledContent("Trajets", value: "\(limits.tripsUsed()) / \(limits.tripsPerDay)")
                    }
                }
                Section {
                    SubscriptionPlans()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                } header: {
                    Text("Offres")
                } footer: {
                    Text("Le paiement dans l'app arrive bientôt.")
                }
                Section("Avec l'abonnement") {
                    MembershipBenefits()
                        .padding(.vertical, XRadarSpacing.xs)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(XRadarColor.canvas)
        .navigationTitle("Abonnement")
        // Days and counts move on their own: read them fresh.
        .task { await services.account.reload() }
    }

    private static func status(of account: Account?) -> String {
        guard let account else { return "Connecte-toi pour voir ton statut." }
        if account.role == .admin { return "Accès complet, sans limite." }
        if account.isRestricted {
            let ended = account.role == .client ? "Ton abonnement est terminé" : "Ton essai gratuit est terminé"
            return "\(ended) : la carte reste disponible ; la navigation, les alertes et les signalements reviennent avec un abonnement."
        }
        if account.role == .client { return "Navigation, alertes et signalements sans limite." }
        let perDay = account.limits.map { "\($0.reportsPerDay) signalements et \($0.tripsPerDay) trajets par jour" } ?? "avec des limites par jour"
        return "Essai gratuit jusqu'au \(AccountLabels.shortDate(account.accessEndsAt)), \(perDay)."
    }
}
