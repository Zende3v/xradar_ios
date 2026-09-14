import SwiftUI
import XRadarCore
import XRadarData

/// "Menu", full screen over the HUD like the Android route: who you are (avatar, email, trust
/// stars, access), the sections, the admin-only referral page, and sign-out at the bottom.
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
                        XRadarListRow(title: "Mon compte", icon: .symbol(.user), tint: XRadarColor.accent)
                    }
                    NavigationLink {
                        StatsScreen(account: services.account)
                    } label: {
                        XRadarListRow(title: "Statistiques", icon: .symbol(.stats), tint: XRadarColor.radarMobile)
                    }
                    NavigationLink {
                        SettingsScreen(services: services)
                    } label: {
                        XRadarListRow(title: "Réglages", icon: .symbol(.settings), tint: XRadarColor.textSecondary)
                    }
                    if account?.role == .admin {
                        NavigationLink {
                            ReferralScreen(account: services.account)
                        } label: {
                            XRadarListRow(title: "Parrainage", icon: .symbol(.referral), tint: XRadarColor.controlZone)
                        }
                    }
                }

                Section {
                    Button {
                        services.account.logout()
                    } label: {
                        Text("Se déconnecter")
                            .font(.xrBodyStrong)
                            .foregroundStyle(XRadarColor.danger)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(XRadarColor.canvas)
            .navigationTitle("Menu")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(XRadarSymbol.close)
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
        HStack(spacing: XRadarSpacing.md) {
            AvatarView(url: account?.avatarUrl, initial: name, size: 64)
            VStack(alignment: .leading, spacing: XRadarSpacing.xs) {
                Text(account?.email ?? name)
                    .font(.xrHeadline)
                    .foregroundStyle(XRadarColor.textPrimary)
                    .lineLimit(1)
                TrustStars(score: account?.trust ?? 2.5)
                XRadarBadge(text: AccountLabels.access(account, nowMillis: nowMillis()), color: accessColor(account))
            }
        }
        .padding(.vertical, XRadarSpacing.xs)
    }
}

/// Circular avatar: the photo at [url], or the first letter of [initial] while there is none.
struct AvatarView: View {
    let url: String?
    let initial: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(XRadarColor.accent.opacity(0.16))
            AsyncImage(url: url.flatMap { URL(string: $0) }) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(String(initial.prefix(1)).uppercased())
                        .font(.xrTitleLarge)
                        .foregroundStyle(XRadarColor.accent)
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
                Image(XRadarSymbol.starFill)
                    .font(.system(size: 13))
                    .foregroundStyle(fill >= 1 ? XRadarColor.warning : fill >= 0.5 ? XRadarColor.warning.opacity(0.55) : XRadarColor.borderStrong)
            }
            Text(AccountLabels.trustLabel(score))
                .font(.xrCaption)
                .foregroundStyle(XRadarColor.textTertiary)
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

func accessColor(_ account: Account?) -> Color {
    guard let account else { return XRadarColor.textSecondary }
    if account.role == .admin { return XRadarColor.accent }
    if account.access == .restricted || !account.canNavigate { return XRadarColor.hazard }
    if account.access == .trial { return XRadarColor.warning }
    return XRadarColor.success
}

func nowMillis() -> Int {
    Int(Date().timeIntervalSince1970 * 1000)
}
