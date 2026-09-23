import SwiftUI
import UIKit
import EonaCore
import EonaData

/// The group on the HUD, over the main map: a chip for everyone at once, then one per member —
/// picture, name, what they are doing. A tap on the photo opens their card; on the name, the
/// camera follows them; again, back to me. It reads only the chips, refreshed at each group tick:
/// the rest of the HUD is not redrawn.
struct GroupStrip: View {
    let model: DriveModel
    /// Everyone at once: the camera frames the whole group.
    let onOverview: () -> Void
    /// Follow this member (nil: back to me).
    let onFocus: (String?) -> Void
    /// Their photo: their card.
    let onCard: (String) -> Void

    var body: some View {
        if !model.groupChips.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: EonaSpacing.sm) {
                    Button(action: onOverview) {
                        HStack(spacing: EonaSpacing.xs) {
                            Image(EonaSymbol.people)
                                .font(.system(size: 13, weight: .semibold))
                            Text("Tous")
                                .font(.xrCaption)
                        }
                        .foregroundStyle(EonaColor.textPrimary)
                        .padding(.horizontal, EonaSpacing.md)
                        .frame(height: 40)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Voir tout le groupe")

                    ForEach(model.groupChips) { chip in
                        memberChip(chip)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func memberChip(_ chip: GroupChip) -> some View {
        let focused = model.groupFocus == chip.id
        let color = GroupPalette.color(chip.colorIndex)
        // Two targets on one capsule: the photo opens the card, the rest follows on the map.
        return HStack(spacing: EonaSpacing.sm) {
            Button {
                onCard(chip.id)
            } label: {
                GroupAvatar(url: chip.avatarURL, name: chip.name, color: color, size: 30)
                    .frame(width: 40, height: 40)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .padding(.trailing, -5)
            .accessibilityLabel("Fiche de \(chip.name)")

            Button {
                onFocus(focused ? nil : chip.id)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(chip.name)
                        .font(.xrCaption.weight(.semibold))
                        .foregroundStyle(EonaColor.textPrimary)
                        .lineLimit(1)
                    Text(chip.detail)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(EonaColor.textSecondary)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
                .padding(.trailing, EonaSpacing.md)
                .frame(height: 40)
                .contentShape(.rect)
                .opacity(chip.onMap ? 1 : 0.6)
            }
            .buttonStyle(.plain)
            // Not on the map: nothing to follow, but the card still opens.
            .disabled(!chip.onMap)
            .accessibilityLabel("\(chip.name), \(chip.detail)")
            .accessibilityHint(chip.onMap ? (focused ? "Revenir sur moi" : "Suivre sur la carte") : "")
        }
        .frame(height: 40)
        .glassEffect(
            focused ? Glass.regular.tint(color.opacity(0.35)).interactive() : Glass.regular.interactive(),
            in: .capsule
        )
        .overlay {
            Capsule().strokeBorder(focused ? color : .clear, lineWidth: 1.5)
        }
        .animation(.smooth(duration: 0.3), value: chip.detail)
    }
}

/// A member's picture in a ring of their colour, their initial while it loads or when there is none.
struct GroupAvatar: View {
    let url: URL?
    let name: String
    let color: Color
    let size: CGFloat

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(color)
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(white: 0.12))
                }
            }
            .clipShape(.circle)
            .padding(2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: url) {
            image = AvatarCache.shared.image(url)
            guard image == nil, let url else { return }
            AvatarCache.shared.load(url) { loaded in image = loaded }
        }
    }
}

/// The group trip is over: the ranking, on the HUD, until the driver closes it.
struct GroupFinishCard: View {
    let model: DriveModel

    var body: some View {
        if let finished = model.finishedGroup {
            VStack(alignment: .leading, spacing: EonaSpacing.md) {
                HStack {
                    Text(finished.toLabel.map { "Arrivés à \($0)" } ?? "Trajet en groupe terminé")
                        .font(.xrHeadline)
                        .foregroundStyle(EonaColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: EonaSpacing.sm)
                    EonaIconButton(icon: .symbol(.close), label: "Fermer", size: 36, glass: false) {
                        model.dismissGroup()
                    }
                }
                GroupRankingView(entries: finished.ranking, mineId: model.myAccountId)
            }
            .padding(EonaSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: EonaRadius.lg))
        }
    }
}
