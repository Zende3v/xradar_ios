import SwiftUI
import EonaData

/// The terms of use, and the act of accepting them. Shown at first launch, and again only when a
/// new version has to be agreed to. A summary comes first, the whole text is one tap away, and
/// the box is empty until the driver ticks it themselves.
struct TermsScreen: View {
    let preferences: PreferencesStore
    let account: AccountStore

    @State private var ticked = false
    @State private var fullTextOpen = false
    @State private var declined = false

    var body: some View {
        if declined {
            declinedView
        } else {
            acceptView
        }
    }

    // MARK: Accepting

    private var acceptView: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.lg) {
            VStack(alignment: .leading, spacing: EonaSpacing.xs) {
                Text("Conditions générales d'utilisation")
                    .font(.xrTitle)
                    .foregroundStyle(EonaColor.textPrimary)
                Text("Version \(Terms.version) · à lire avant d'utiliser EONA")
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textTertiary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: EonaSpacing.md) {
                    Text("En bref")
                        .font(.xrBodyStrong)
                        .foregroundStyle(EonaColor.textPrimary)
                    ForEach(Terms.summary, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: EonaSpacing.sm) {
                            Circle()
                                .fill(EonaColor.accent)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(line)
                                .font(.xrBody)
                                .foregroundStyle(EonaColor.textSecondary)
                        }
                    }
                    Text("Le résumé ne remplace pas le texte : seules les conditions complètes engagent.")
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                fullTextOpen = true
            } label: {
                HStack {
                    Text("Lire les conditions complètes")
                        .font(.xrBodyStrong)
                        .foregroundStyle(EonaColor.accent)
                    Spacer(minLength: 0)
                    EonaIconView(icon: .symbol(.chevronRight), size: 16)
                        .foregroundStyle(EonaColor.textTertiary)
                }
                .padding(EonaSpacing.md)
                .background(EonaColor.surface, in: .rect(cornerRadius: EonaRadius.md))
            }
            .buttonStyle(.plain)

            Button {
                ticked.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: EonaSpacing.sm) {
                    EonaIconView(icon: .symbol(ticked ? .checkSquare : .square), size: 22)
                        .foregroundStyle(ticked ? EonaColor.accent : EonaColor.textSecondary)
                    Text("J'ai lu et j'accepte les Conditions générales d'utilisation")
                        .font(.xrBody)
                        .foregroundStyle(EonaColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(ticked ? [.isSelected] : [])

            VStack(spacing: EonaSpacing.sm) {
                EonaButton(title: "Accepter", fillWidth: true) { accept() }
                    .disabled(!ticked)
                    .opacity(ticked ? 1 : 0.5)
                EonaButton(title: "Refuser", variant: .secondary, fillWidth: true) {
                    preferences.declineTerms()
                    declined = true
                }
            }
        }
        .padding(EonaSpacing.lg)
        .background(EonaColor.canvas)
        .sheet(isPresented: $fullTextOpen) {
            TermsTextScreen { fullTextOpen = false }
        }
    }

    // MARK: Refused

    private var declinedView: some View {
        VStack(spacing: EonaSpacing.lg) {
            Spacer(minLength: 0)
            EonaIconView(icon: .symbol(.info), size: 40)
                .foregroundStyle(EonaColor.textSecondary)
            Text("EONA ne peut pas démarrer")
                .font(.xrTitle)
                .foregroundStyle(EonaColor.textPrimary)
                .multilineTextAlignment(.center)
            Text("La navigation, les alertes et le compte reposent sur ces conditions. Sans accord, elles restent inactives. Tu peux relire le texte et revenir dessus quand tu veux.")
                .font(.xrBody)
                .foregroundStyle(EonaColor.textSecondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            VStack(spacing: EonaSpacing.sm) {
                EonaButton(title: "Relire les conditions", fillWidth: true) { fullTextOpen = true }
                EonaButton(title: "Revenir à l'acceptation", variant: .secondary, fillWidth: true) {
                    declined = false
                    ticked = false
                }
            }
        }
        .padding(EonaSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EonaColor.canvas)
        .sheet(isPresented: $fullTextOpen) {
            TermsTextScreen { fullTextOpen = false }
        }
    }

    private func accept() {
        preferences.acceptTerms(version: Terms.version)
        // The account keeps the proof too: which version, and when.
        Task { await account.recordTerms(version: Terms.version) }
    }
}

/// The whole text, as shipped with the app so it reads without a connection.
struct TermsTextScreen: View {
    var onClose: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EonaSpacing.md) {
                    ForEach(Array(Terms.paragraphs.enumerated()), id: \.offset) { _, block in
                        if block.hasPrefix("## ") {
                            Text(block.dropFirst(3))
                                .font(.xrBodyStrong)
                                .foregroundStyle(EonaColor.textPrimary)
                                .padding(.top, EonaSpacing.sm)
                        } else {
                            Text(block)
                                .font(.xrBody)
                                .foregroundStyle(EonaColor.textSecondary)
                        }
                    }
                    Link("Voir la version en ligne", destination: Terms.url)
                        .font(.xrFootnote)
                        .padding(.top, EonaSpacing.md)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EonaSpacing.lg)
                .textSelection(.enabled)
            }
            .scrollContentBackground(.hidden)
            .background(EonaColor.canvas)
            .navigationTitle("Conditions d'utilisation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer") { onClose() }
                    }
                }
            }
        }
    }
}

/// The terms as the app carries them: the version that must be agreed to, the summary, the text.
enum Terms {
    /// Bump this when a change needs the driver to agree again — not for a typo.
    static let version = "1.1"
    static let url = URL(string: "https://cgu.zylo-app.fr")!

    static let summary = [
        "EONA aide à la conduite : elle ne remplace ni la signalisation, ni ta vigilance. Tu restes seul responsable au volant.",
        "L'application est réservée aux personnes d'au moins 17 ans.",
        "Les signalements des conducteurs et les données des partenaires peuvent être inexacts ou en retard.",
        "Tes signalements servent à tout le monde ; l'éditeur ne vend aucune donnée.",
        "Partager ton trajet ou rouler en groupe est facultatif : ta position ne part que si tu l'acceptes, et se coupe quand tu veux. Faire suivre quelqu'un à son insu est interdit.",
        "Un compte peut être suspendu en cas d'abus : faux signalements, usage détourné, contenu illicite.",
        "Le détail des données, de leur durée et de tes droits est dans la politique de confidentialité.",
    ]

    /// The text shipped with the app, split into blocks ("## " marks a heading).
    static let paragraphs: [String] = {
        guard let url = Bundle.main.url(forResource: "CGU", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return ["Les conditions ne sont pas disponibles hors connexion. Ouvre cgu.zylo-app.fr."] }
        return text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }()
}
