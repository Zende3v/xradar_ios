import SwiftUI
import EonaCore
import EonaData

/// Which member's card is open, and in which colour they are drawn.
struct MemberCardTarget: Identifiable, Hashable {
    let id: String
    let colorIndex: Int
}

/// A member's card, opened from their photo — in the strip, on the map or in the group's list:
/// who they are (photo, name, status, since when), how much the others trust their reports, how
/// they drive, and where they stand in this trip. The live part follows the group's news; the
/// rest is read once. A driver who hid their statistics shows the first part only.
struct MemberCardSheet: View {
    let model: DriveModel
    let target: MemberCardTarget
    /// Follow them on the map; nil where there is no map to follow them on.
    var onFollow: ((String) -> Void)?

    @State private var card: MemberCard?
    @State private var failed = false

    private var color: Color { GroupPalette.color(target.colorIndex) }
    private var isMe: Bool { target.id == model.myAccountId }
    /// The strip's line for them: fresher than the card, it moves with every position.
    private var liveDetail: String? { model.groupChips.first { $0.id == target.id }?.detail }
    private var onMap: Bool { model.groupChips.first { $0.id == target.id }?.onMap == true }

    var body: some View {
        ScrollView {
            VStack(spacing: EonaSpacing.lg) {
                if let card {
                    header(card)
                    trust(card)
                    trip(card)
                    stats(card)
                    if let onFollow, onMap, !isMe {
                        EonaButton(title: "Suivre sur la carte", systemImage: .navigation, fillWidth: true) {
                            onFollow(card.id)
                        }
                    }
                } else if failed {
                    EonaMessageState(
                        icon: .symbol(.info),
                        title: "Fiche indisponible",
                        message: "Ce conducteur n'est plus dans le groupe, ou le réseau ne répond pas."
                    )
                    .padding(.top, EonaSpacing.xxl)
                } else {
                    EonaLoadingState(label: "Chargement…")
                        .padding(.top, EonaSpacing.xxl)
                }
            }
            .padding(.horizontal, EonaSpacing.lg)
            .padding(.top, EonaSpacing.xl)
            .padding(.bottom, EonaSpacing.xxl)
            .animation(.smooth(duration: 0.3), value: card)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task(id: target.id) {
            // Read at once, then again now and then while it is open: the state and the rank move.
            while !Task.isCancelled {
                if let fresh = await model.memberCard(target.id) {
                    card = fresh
                } else if card == nil {
                    failed = true
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    // MARK: Parts

    private func header(_ card: MemberCard) -> some View {
        VStack(spacing: EonaSpacing.sm) {
            GroupAvatar(url: card.avatarURL, name: card.name, color: color, size: 96)
                .shadow(color: color.opacity(0.45), radius: 16)
            Text(isMe ? "\(card.name) (moi)" : card.name)
                .font(.xrTitle)
                .foregroundStyle(EonaColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: EonaSpacing.xs) {
                EonaBadge(text: card.role.label, glow: card.role != .guest)
                if card.isHost {
                    EonaBadge(text: "Mène le groupe", color: color)
                }
            }
            if let since = card.memberSinceLabel {
                Text(since)
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func trust(_ card: MemberCard) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Note de confiance")
                    .font(.xrBodyStrong)
                    .foregroundStyle(EonaColor.textPrimary)
                Text("Ses signalements confirmés par les autres")
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textTertiary)
            }
            Spacer(minLength: EonaSpacing.sm)
            TrustStars(score: card.trust)
        }
        .xrSheetCard()
    }

    /// Where they stand in this trip.
    private func trip(_ card: MemberCard) -> some View {
        let member = card.live
        return VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            Text("Dans ce trajet")
                .font(.xrCaption)
                .foregroundStyle(EonaColor.textTertiary)
            HStack(spacing: EonaSpacing.md) {
                Circle()
                    .fill(member.state == .driving && member.online ? color : EonaColor.textTertiary)
                    .frame(width: 10, height: 10)
                Text(member.state == .arrived ? arrivedLabel(member) : (liveDetail ?? member.detailLabel))
                    .font(.xrBodyStrong.monospacedDigit())
                    .foregroundStyle(EonaColor.textPrimary)
                    .contentTransition(.numericText())
                    .lineLimit(2)
                Spacer(minLength: 0)
                if let rank = member.rank {
                    Label(rank == 1 ? "1er" : "\(rank)e", systemImage: EonaSymbol.trophy.rawValue)
                        .font(.xrCaption.weight(.semibold))
                        .foregroundStyle(rank == 1 ? EonaColor.warning : EonaColor.textSecondary)
                }
            }
            if member.sharing, member.state == .driving, let eta = member.etaAt {
                Text("Arrivée prévue à \(eta.formatted(date: .omitted, time: .shortened))")
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .xrSheetCard()
        .animation(.smooth(duration: 0.3), value: liveDetail)
    }

    @ViewBuilder
    private func stats(_ card: MemberCard) -> some View {
        if let stats = card.stats {
            VStack(alignment: .leading, spacing: EonaSpacing.md) {
                Text("Au volant avec EONA")
                    .font(.xrCaption)
                    .foregroundStyle(EonaColor.textTertiary)
                HStack(spacing: EonaSpacing.sm) {
                    tile(StatsLabels.kilometers(meters: stats.distanceMeters), "Parcourus", color)
                    tile(StatsLabels.hours(seconds: stats.driveDurationSeconds), "Sur la route", EonaColor.textPrimary)
                    tile(StatsLabels.grouped(stats.tripCount), "Trajets", EonaColor.textPrimary)
                }
                Divider().overlay(EonaColor.separator)
                row("Signalements déclarés", StatsLabels.grouped(stats.reportsDeclared))
                row("Confirmés par d'autres", StatsLabels.grouped(stats.reportsConfirmed))
            }
            .xrSheetCard()
        } else {
            HStack(spacing: EonaSpacing.md) {
                EonaIconView(icon: .symbol(.eyeSlash), size: 18)
                    .foregroundStyle(EonaColor.textTertiary)
                Text(isMe
                     ? "Tu caches tes statistiques au groupe (Menu ▸ Confidentialité)."
                     : "\(card.name) garde ses statistiques pour lui.")
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textSecondary)
                Spacer(minLength: 0)
            }
            .xrSheetCard()
        }
    }

    private func tile(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: EonaSpacing.xs) {
            Text(value)
                .font(.xrHeadline.monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.xrCaption)
                .foregroundStyle(EonaColor.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, EonaSpacing.sm)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.xrBody)
                .foregroundStyle(EonaColor.textSecondary)
            Spacer()
            Text(value)
                .font(.xrBodyStrong.monospacedDigit())
                .foregroundStyle(EonaColor.textPrimary)
        }
    }

    /// "Arrivé en 2h05 · 184 km".
    private func arrivedLabel(_ member: GroupMember) -> String {
        var parts = ["Arrivé"]
        if let seconds = member.durationSeconds { parts[0] += " en " + StatsLabels.hours(seconds: seconds) }
        if let metres = member.distanceMeters { parts.append(StatsLabels.kilometers(meters: metres)) }
        return parts.joined(separator: " · ")
    }
}
