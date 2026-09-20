import SwiftUI
import EonaCore
import EonaData

/// "Menu", full screen over the HUD like the Android route: who you are (avatar, email, trust
/// stars, access), the sections (Confidentialité among them), the admin-only referral page,
/// "À propos" (the legal notices), and sign-out at the bottom. Its icons and the access badge glow white on dark tiles.
struct MenuScreen: View {
    let services: AppServices
    let onClose: () -> Void

    var body: some View {
        let account = services.account.account
        NavigationStack {
            Form {
                Section {
                    MenuIdentity(account: account)
                }

                Section {
                    NavigationLink {
                        ProfileScreen(services: services)
                    } label: {
                        EonaListRow(title: "Mon compte", icon: .symbol(.user), glow: true)
                    }
                    NavigationLink {
                        SubscriptionScreen(services: services)
                    } label: {
                        EonaListRow(title: "Abonnement", icon: .symbol(.crown), glow: true)
                    }
                    NavigationLink {
                        StatsScreen(account: services.account)
                    } label: {
                        EonaListRow(title: "Statistiques", icon: .symbol(.stats), glow: true)
                    }
                    NavigationLink {
                        SettingsScreen(services: services)
                    } label: {
                        EonaListRow(title: "Réglages", icon: .symbol(.settings), glow: true)
                    }
                    NavigationLink {
                        PrivacyScreen(services: services)
                    } label: {
                        EonaListRow(title: "Confidentialité", icon: .symbol(.privacy), glow: true)
                    }
                    if account?.role == .admin {
                        NavigationLink {
                            ReferralScreen(account: services.account)
                        } label: {
                            EonaListRow(title: "Parrainage", icon: .symbol(.referral), glow: true)
                        }
                        NavigationLink {
                            BugListScreen(services: services)
                        } label: {
                            EonaListRow(title: "Rapports de bugs", icon: .symbol(.bug), glow: true)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        BugReportScreen(services: services)
                    } label: {
                        EonaListRow(title: "Signaler un bug", icon: .symbol(.bug), glow: true)
                    }
                    NavigationLink {
                        LegalScreen()
                    } label: {
                        EonaListRow(title: "À propos", icon: .symbol(.info), glow: true)
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
