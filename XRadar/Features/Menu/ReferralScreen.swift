import SwiftUI
import UIKit
import XRadarCore
import XRadarData

/// Parrainage (admin only): mint codes worth 6 months of membership and see how many accounts
/// used each. A code is only accepted when an account is created.
struct ReferralScreen: View {
    let account: AccountStore

    @State private var codes: [ReferralCode] = []
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                XRadarButton(title: "Générer un code (6 mois de membre)", loading: busy, fillWidth: true) {
                    create()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                if let message {
                    Text(message)
                        .font(.xrFootnote)
                        .foregroundStyle(XRadarColor.accent)
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                if codes.isEmpty {
                    Text("Aucun code pour l'instant")
                        .foregroundStyle(XRadarColor.textSecondary)
                } else {
                    ForEach(codes, id: \.code) { code in
                        Button {
                            UIPasteboard.general.string = code.code
                            message = "\(code.code) copié."
                        } label: {
                            XRadarListRow(title: code.code, subtitle: "Créé le \(AccountLabels.shortDate(code.createdAt)) · \(code.months) mois") {
                                Text(code.redemptions == 1 ? "1 utilisation" : String("\(code.redemptions) utilisations"))
                                    .font(.xrCallout)
                                    .foregroundStyle(code.redemptions > 0 ? XRadarColor.success : XRadarColor.textTertiary)
                            }
                        }
                    }
                }
            } header: {
                Text("Mes codes")
            } footer: {
                Text("Un code se saisit uniquement à la création du compte. Touche un code pour le copier.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(XRadarColor.canvas)
        .navigationTitle("Parrainage")
        .task { codes = await account.referrals() }
    }

    private func create() {
        busy = true
        Task {
            if let created = await account.createReferral() {
                UIPasteboard.general.string = created.code
                message = "Code \(created.code) créé et copié."
                codes = [created] + codes
            } else {
                message = "Création impossible — réseau ou droits admin."
            }
            busy = false
        }
    }
}
