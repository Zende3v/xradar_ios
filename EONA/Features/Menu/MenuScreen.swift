import SwiftUI
import EonaCore
import EonaData

/// « Menu », plein écran sur le HUD : identité, puis trois boîtes. 1 : Réglages, EONA +, Mon compte
/// & Statistiques, Confidentialité, À propos. 2 : « Contactez-nous ». 3, admins seulement :
/// Gestion EONA, Parrainage, Rapports. Déconnexion en bas.
struct MenuScreen: View {
    let services: AppServices
    let onClose: () -> Void

    @State private var contactOpen = false

    var body: some View {
        let account = services.account.account
        NavigationStack {
            Form {
                Section {
                    MenuIdentity(account: account)
                }

                Section {
                    NavigationLink {
                        SettingsScreen(services: services)
                    } label: {
                        EonaListRow(title: "Réglages", icon: .symbol(.settings), glow: true)
                    }
                    NavigationLink {
                        SubscriptionScreen(services: services)
                    } label: {
                        EonaListRow(title: "EONA +", icon: .asset(.premium), glow: true)
                    }
                    NavigationLink {
                        ProfileScreen(services: services)
                    } label: {
                        EonaListRow(title: "Mon compte & Statistiques", icon: .symbol(.user), glow: true)
                    }
                    NavigationLink {
                        PrivacyScreen(services: services)
                    } label: {
                        EonaListRow(title: "Confidentialité", icon: .symbol(.privacy), glow: true)
                    }
                    NavigationLink {
                        LegalScreen(
                            acceptedVersion: services.preferences.settings.termsVersion,
                            acceptedAt: services.preferences.settings.termsAcceptedAt
                        )
                    } label: {
                        EonaListRow(title: "À propos", icon: .symbol(.info), glow: true)
                    }
                }

                // Carte bordée à part : ses bords, pas ceux de la liste.
                Section {
                    Button {
                        contactOpen = true
                    } label: {
                        ContactCard()
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if account?.role == .admin {
                    Section {
                        NavigationLink {
                            EonaAdminScreen(services: services)
                        } label: {
                            EonaListRow(title: "Gestion EONA", icon: .symbol(.stats), glow: true)
                        }
                        NavigationLink {
                            ReferralScreen(account: services.account)
                        } label: {
                            EonaListRow(title: "Parrainage", icon: .symbol(.referral), glow: true)
                        }
                        NavigationLink {
                            BugListScreen(services: services)
                        } label: {
                            EonaListRow(title: "Rapports", icon: .symbol(.bug), glow: true)
                        }
                    } header: {
                        Text("Admin")
                    }
                }

                Section {
                    Button {
                        services.account.logout()
                    } label: {
                        Text("Se déconnecter")
                            .font(.xrBodyStrong)
                            .foregroundStyle(EonaColor.danger)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(EonaColor.canvas)
            .navigationTitle("Menu")
            .navigationDestination(isPresented: $contactOpen) {
                BugReportScreen(services: services)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(EonaSymbol.close)
                    }
                    .accessibilityLabel("Fermer")
                }
            }
        }
        // The access status moves on its own (trial ending, referral applied): refresh.
        .task { await services.account.reload() }
    }
}

/// « Un problème, une suggestion ? » — « Contactez-nous ! » : bugs et idées, un seul formulaire.
private struct ContactCard: View {
    var body: some View {
        HStack(spacing: EonaSpacing.md) {
            Image(EonaSymbol.contact)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(EonaColor.accent)
                .frame(width: 40, height: 40)
                .background(EonaColor.accent.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("Un problème, une suggestion ?")
                    .font(.xrBodyStrong)
                    .foregroundStyle(EonaColor.textPrimary)
                Text("Contactez-nous !")
                    .font(.xrSubhead)
                    .foregroundStyle(EonaColor.accent)
            }
            Spacer(minLength: 0)
            Image(EonaSymbol.chevronRight)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(EonaColor.textTertiary)
        }
        .padding(EonaSpacing.lg)
        .background(EonaColor.surface, in: .rect(cornerRadius: EonaRadius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: EonaRadius.xl)
                .strokeBorder(EonaColor.accent.opacity(0.55), lineWidth: 1.5)
        }
        .contentShape(.rect(cornerRadius: EonaRadius.xl))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Avatar (or the initial in a circle), email, trust stars and access status.
private struct MenuIdentity: View {
    let account: Account?

    var body: some View {
        let name = displayName(of: account)
        HStack(spacing: EonaSpacing.md) {
            AvatarView(url: account?.avatarUrl, initial: name, size: 64)
            VStack(alignment: .leading, spacing: EonaSpacing.xs) {
                Text(account?.email ?? name)
                    .font(.xrHeadline)
                    .foregroundStyle(EonaColor.textPrimary)
                    .lineLimit(1)
                TrustStars(score: account?.trust ?? 2.5)
                EonaBadge(text: AccountLabels.access(account, nowMillis: nowMillis()), glow: true)
            }
        }
        .padding(.vertical, EonaSpacing.xs)
    }
}

/// Circular avatar: the photo at [url], or the first letter of [initial] while there is none.
struct AvatarView: View {
    let url: String?
    let initial: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(EonaColor.accent.opacity(0.16))
            AsyncImage(url: url.flatMap { URL(string: $0) }) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(String(initial.prefix(1)).uppercased())
                        .font(.xrTitleLarge)
                        .foregroundStyle(EonaColor.accent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

/// Five stars filled to the trust score (0...5, half-star precision), then the score.
struct TrustStars: View {
    let score: Double

    var body: some View {
        let rounded = AccountLabels.trustRounded(score)
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                let fill = min(max(rounded - Double(index), 0), 1)
                Image(EonaSymbol.starFill)
                    .font(.system(size: 13))
                    .foregroundStyle(fill >= 1 ? EonaColor.warning : fill >= 0.5 ? EonaColor.warning.opacity(0.55) : EonaColor.borderStrong)
            }
            Text(AccountLabels.trustLabel(score))
                .font(.xrCaption)
                .foregroundStyle(EonaColor.textTertiary)
                .padding(.leading, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Note de confiance \(AccountLabels.trustLabel(score)) sur 5")
    }
}

/// The display name, else the role.
func displayName(of account: Account?) -> String {
    if let name = account?.displayName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return name
    }
    return (account?.role ?? .guest).label
}

func nowMillis() -> Int {
    Int(Date().timeIntervalSince1970 * 1000)
}
