import SwiftUI
import UIKit
import EonaCore
import EonaData

/// First screen for a phone without a chosen username, as on Android: create an account, sign in,
/// or continue as a guest (username + password), plus the forgotten password flow. A success
/// updates the account and the app root moves on by itself.
struct OnboardingView: View {
    let account: AccountStore

    private enum Mode {
        case choose, guest, login, register, forgot, reset
    }

    @State private var mode = Mode.choose
    @State private var pseudo = ""
    @State private var email = ""
    @State private var password = ""
    @State private var referral = ""
    @State private var code = ""
    @State private var loading = false
    @State private var error: String?
    @State private var info: String?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: EonaSpacing.md) {
                    Text("EONA")
                        .font(.xrDisplayHero)
                        .foregroundStyle(EonaColor.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let subtitle {
                        Text(subtitle)
                            .font(.xrSubhead)
                            .foregroundStyle(EonaColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    VStack(spacing: EonaSpacing.sm) {
                        form
                        if let error {
                            note(error, color: EonaColor.hazard)
                        }
                        if let info {
                            note(info, color: EonaColor.accent)
                        }
                    }
                    .padding(.top, EonaSpacing.lg)
                }
                .frame(maxWidth: 420)
                .padding(EonaSpacing.xl)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(EonaColor.canvas)
        .animation(.snappy, value: mode)
        .accessibilityIdentifier("screen.onboarding")
    }

    private var subtitle: String? {
        switch mode {
        case .choose: nil
        case .guest: "Choisis un pseudo et un mot de passe."
        case .login: "Content de te revoir."
        case .register: "7 jours d'essai gratuit — ou un code de parrainage."
        case .forgot: "Reçois un code par email."
        case .reset: "Entre le code reçu et ton nouveau mot de passe."
        }
    }

    @ViewBuilder
    private var form: some View {
        switch mode {
        case .choose:
            EonaButton(title: "Créer un compte", fillWidth: true) {
                mode = .register
            }
            EonaButton(title: "Se connecter", variant: .secondary, fillWidth: true) {
                mode = .login
                error = nil
            }
            EonaButton(title: "Continuer en invité", variant: .secondary, fillWidth: true) {
                mode = .guest
                error = nil
            }

        case .guest:
            field("Pseudo", text: trimmed($pseudo), content: .username)
            secureField("Mot de passe (8 min.)", text: $password, content: .newPassword)
            Text("Il sert à retrouver ton compte si tu réinstalles l'app. Un compte invité est supprimé au bout de 7 jours.")
                .font(.xrFootnote)
                .foregroundStyle(EonaColor.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            submit("Continuer") {
                await account.claimGuest(username: pseudo, password: password)
            }
            back { mode = .choose; error = nil }

        case .login:
            field("Email ou pseudo", text: trimmed($email), content: .username, keyboard: .emailAddress)
            secureField("Mot de passe", text: $password, content: .password)
            submit("Se connecter") {
                await account.login(identifier: email, password: password)
            }
            back("Mot de passe oublié ?") { mode = .forgot; error = nil; info = nil }
            back { mode = .choose; error = nil }

        case .register:
            field("Pseudo", text: trimmed($pseudo), content: .username)
            field("Email", text: trimmed($email), content: .emailAddress, keyboard: .emailAddress)
            secureField("Mot de passe (8 min.)", text: $password, content: .newPassword)
            // Only here, at creation: a code turns the new account into 6 months of membership.
            field("Code de parrainage (facultatif)", text: referralBinding, content: nil, caps: .characters)
            submit("Créer le compte") {
                await account.register(email: email, password: password, username: pseudo, referralCode: referral.isEmpty ? nil : referral)
            }
            back { mode = .choose; error = nil }

        case .forgot:
            field("Email", text: trimmed($email), content: .emailAddress, keyboard: .emailAddress)
            run("Envoyer le code") {
                await account.forgot(email: email)
                info = "Si un compte existe, un code a été envoyé."
                mode = .reset
                return nil
            }
            back { mode = .login; error = nil; info = nil }

        case .reset:
            field("Code reçu par email", text: trimmed($code), content: .oneTimeCode, keyboard: .numberPad)
            secureField("Nouveau mot de passe (8 min.)", text: $password, content: .newPassword)
            run("Réinitialiser") {
                let failure = await account.resetPassword(email: email, code: code, password: password)
                if failure == nil {
                    info = "Mot de passe changé, connecte-toi."
                    password = ""
                    code = ""
                    mode = .login
                }
                return failure
            }
            back { mode = .login; error = nil; info = nil }
        }
    }

    // MARK: Actions

    /// An auth call: its failure shows under the form; its success moves the app on.
    private func submit(_ title: String, _ call: @escaping @MainActor () async -> AuthOutcome) -> some View {
        EonaButton(title: title, loading: loading, fillWidth: true) {
            error = nil
            loading = true
            Task {
                let outcome = await call()
                loading = false
                if case .failure(let message) = outcome { error = message }
            }
        }
    }

    /// A call that answers nil on success, else a message.
    private func run(_ title: String, _ call: @escaping @MainActor () async -> String?) -> some View {
        EonaButton(title: title, loading: loading, fillWidth: true) {
            error = nil
            info = nil
            loading = true
            Task {
                let failure = await call()
                loading = false
                if let failure { error = failure }
            }
        }
    }

    // MARK: Pieces

    private func trimmed(_ binding: Binding<String>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    private var referralBinding: Binding<String> {
        Binding(
            get: { referral },
            set: { referral = $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    private func field(
        _ placeholder: String,
        text: Binding<String>,
        content: UITextContentType?,
        keyboard: UIKeyboardType = .default,
        caps: TextInputAutocapitalization = .never
    ) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(EonaColor.textTertiary))
            .textContentType(content)
            .keyboardType(keyboard)
            .textInputAutocapitalization(caps)
            .autocorrectionDisabled()
            .modifier(FieldStyle())
    }

    private func secureField(_ placeholder: String, text: Binding<String>, content: UITextContentType) -> some View {
        SecureField("", text: text, prompt: Text(placeholder).foregroundStyle(EonaColor.textTertiary))
            .textContentType(content)
            .modifier(FieldStyle())
    }

    private func back(_ title: String = "Retour", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.xrSubhead)
                .foregroundStyle(EonaColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, EonaSpacing.sm)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.xrFootnote)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

/// The onboarding text field: surface fill, hairline border.
private struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.xrBody)
            .foregroundStyle(EonaColor.textPrimary)
            .tint(EonaColor.accent)
            .padding(EonaSpacing.md)
            .background(EonaColor.surface, in: .rect(cornerRadius: EonaRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: EonaRadius.md)
                    .strokeBorder(EonaColor.border, lineWidth: 1)
            }
    }
}
