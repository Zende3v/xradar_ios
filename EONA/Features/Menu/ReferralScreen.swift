import SwiftUI
import UIKit
import EonaCore
import EonaData

/// Parrainage (admin only): mint codes worth months of membership, choose how long a new code
/// stays usable, and act on the ones already out — extend, revoke, replace. A code is only
/// accepted when an account is created.
struct ReferralScreen: View {
    let account: AccountStore

    @State private var codes: [ReferralCode] = []
    @State private var settings: ReferralSettings?
    /// What the slider shows while it is being dragged; saved when it is let go.
    @State private var months: Double = 3
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                validitySlider
            } header: {
                Text("Durée de validité")
            } footer: {
                Text("Elle s'applique aux codes créés ensuite. Les codes déjà distribués gardent leur date de fin : seul « Prolonger » la déplace.")
            }

            Section {
                EonaButton(title: "Générer un code", loading: busy, fillWidth: true) {
                    create()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                if let message {
                    Text(message)
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.accent)
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                if codes.isEmpty {
                    Text("Aucun code pour l'instant")
                        .foregroundStyle(EonaColor.textSecondary)
                } else {
                    ForEach(codes, id: \.code) { code in
                        NavigationLink {
                            ReferralDetailScreen(account: account, code: code) { updated in
                                replace(updated)
                            }
                        } label: {
                            row(code)
                        }
                    }
                }
            } header: {
                Text("Mes codes")
            } footer: {
                Text("Un code se saisit uniquement à la création du compte. Ouvre un code pour le copier, le prolonger, le révoquer ou le remplacer.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(EonaColor.canvas)
        .navigationTitle("Parrainage")
        .task { await load() }
    }

    /// One code: how long it grants, when it ends, how often it was used.
    private func row(_ code: ReferralCode) -> some View {
        EonaListRow(title: code.code, subtitle: detail(code)) {
            Text(code.redemptions == 1 ? "1 usage" : "\(code.redemptions) usages")
                .font(.xrCallout)
                .foregroundStyle(code.redemptions > 0 ? EonaColor.success : EonaColor.textTertiary)
        }
    }

    private func detail(_ code: ReferralCode) -> String {
        var parts = ["\(code.months) mois de membre"]
        if code.revokedAt != nil {
            parts.append("révoqué")
        } else if let expiresAt = code.expiresAt {
            parts.append("expire le \(Self.day(expiresAt)) · \(code.remainingLabel)")
        }
        return parts.joined(separator: " · ")
    }

    /// One month to a year, with the choice written out under the slider.
    @ViewBuilder
    private var validitySlider: some View {
        if let settings {
            VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                HStack {
                    Text("Un code reste utilisable")
                        .font(.xrBody)
                        .foregroundStyle(EonaColor.textPrimary)
                    Spacer(minLength: 0)
                    Text(Self.duration(Int(months.rounded())))
                        .font(.xrBodyStrong)
                        .foregroundStyle(EonaColor.accent)
                }
                Slider(
                    value: $months,
                    in: Double(settings.minMonths)...Double(settings.maxMonths),
                    step: 1,
                    onEditingChanged: { editing in
                        if !editing { saveValidity() }
                    }
                )
                .tint(EonaColor.accent)
                HStack {
                    Text(Self.duration(settings.minMonths))
                    Spacer(minLength: 0)
                    Text(Self.duration(settings.maxMonths))
                }
                .font(.xrFootnote)
                .foregroundStyle(EonaColor.textTertiary)
            }
            .padding(.vertical, EonaSpacing.xs)
        } else {
            ProgressView().tint(EonaColor.accent)
        }
    }

    private func load() async {
        async let list = account.referrals()
        async let config = account.referralSettings()
        codes = await list
        if let config = await config {
            settings = config
            months = Double(config.validityMonths)
        }
    }

    private func saveValidity() {
        let chosen = Int(months.rounded())
        guard settings?.validityMonths != chosen else { return }
        Task {
            if await account.setReferralValidity(months: chosen) {
                settings = settings.map {
                    ReferralSettings(validityMonths: chosen, minMonths: $0.minMonths, maxMonths: $0.maxMonths)
                }
                message = "Les prochains codes dureront \(Self.duration(chosen))."
            } else {
                message = "Changement impossible — réseau ou droits admin."
            }
        }
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

    private func replace(_ updated: ReferralCode) {
        if let index = codes.firstIndex(where: { $0.code == updated.code }) {
            codes[index] = updated
        } else {
            codes = [updated] + codes
        }
    }

    /// "1 mois", "3 mois", "1 an".
    static func duration(_ months: Int) -> String {
        months >= 12 ? "1 an" : "\(months) mois"
    }

    static func day(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .omitted)
    }
}

/// One code in full: what it grants, when it ends, what was done to it, and what can still be.
struct ReferralDetailScreen: View {
    let account: AccountStore
    @State var code: ReferralCode
    let onChange: (ReferralCode) -> Void

    @State private var extraMonths: Double = 3
    @State private var busy = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                LabeledContent("Code", value: code.code)
                LabeledContent("Accorde", value: "\(code.months) mois de membre")
                LabeledContent("Créé le", value: AccountLabels.shortDate(code.createdAt))
                if let expiresAt = code.expiresAt {
                    LabeledContent("Expire le", value: ReferralScreen.day(expiresAt))
                    LabeledContent("Temps restant", value: code.remainingLabel)
                }
                LabeledContent("Utilisations", value: "\(code.redemptions)")
                LabeledContent("État", value: code.revokedAt != nil ? "Révoqué" : (code.active ? "Actif" : "Expiré"))
            }

            Section {
                HStack {
                    Text("Prolonger de")
                    Spacer(minLength: 0)
                    Text(ReferralScreen.duration(Int(extraMonths.rounded())))
                        .font(.xrBodyStrong)
                        .foregroundStyle(EonaColor.accent)
                }
                Slider(value: $extraMonths, in: 1...12, step: 1)
                    .tint(EonaColor.accent)
                EonaButton(title: "Prolonger", loading: busy, fillWidth: true) {
                    act("extend", months: Int(extraMonths.rounded()))
                }
                EonaButton(title: "Copier le code", variant: .secondary, fillWidth: true) {
                    UIPasteboard.general.string = code.code
                    message = "Copié."
                }
                EonaButton(title: "Régénérer", variant: .secondary, fillWidth: true) {
                    act("regenerate")
                }
                EonaButton(title: "Révoquer", variant: .secondary, fillWidth: true) {
                    act("revoke")
                }
                if let message {
                    Text(message)
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.accent)
                }
            } footer: {
                Text("Régénérer révoque ce code et en crée un nouveau à sa place. Tout est consigné ci-dessous.")
            }

            if !code.history.isEmpty {
                Section("Historique") {
                    ForEach(Array(code.history.enumerated()), id: \.offset) { _, event in
                        EonaListRow(
                            title: event.label,
                            subtitle: [event.by, event.at.map(ReferralScreen.day)].compactMap { $0 }.joined(separator: " · ")
                        )
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(EonaColor.canvas)
        .navigationTitle(code.code)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func act(_ action: String, months: Int? = nil) {
        busy = true
        Task {
            if let updated = await account.actOnReferral(code: code.code, action: action, months: months) {
                onChange(updated)
                if action == "regenerate" {
                    UIPasteboard.general.string = updated.code
                    message = "Nouveau code \(updated.code), copié."
                    dismiss()
                } else {
                    code = updated
                    message = action == "revoke" ? "Code révoqué." : "Code prolongé."
                }
            } else {
                message = "Action impossible — réseau ou droits admin."
            }
            busy = false
        }
    }
}
