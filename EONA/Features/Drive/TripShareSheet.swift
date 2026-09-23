import SwiftUI
import EonaCore
import EonaData

/// Sharing the trip, two ways: a link somebody follows, or a group of drivers heading for the
/// same address, each on their own road.
///
/// Nothing opens by itself. The link is created when the driver asks for it, and only once the
/// trip has really started: before that there is nothing to follow, and nothing to stop.
struct TripShareSheet: View {
    let model: DriveModel
    let onClose: () -> Void

    @State private var mode: Mode = .link
    @State private var failed = false

    enum Mode: CaseIterable {
        case link
        case group

        var label: String { self == .link ? "Un lien" : "En groupe" }
        var icon: EonaIconImage { self == .link ? .asset(.share) : .symbol(.people) }
    }

    var body: some View {
        VStack(spacing: EonaSpacing.lg) {
            Capsule()
                .fill(EonaColor.borderStrong)
                .frame(width: 40, height: 5)
                .padding(.top, EonaSpacing.sm)

            ShareModePicker(mode: $mode)
                .padding(.horizontal, EonaSpacing.lg)

            switch mode {
            case .link:
                link
                    .transition(.opacity)
            case .group:
                GroupPanel(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            // A group running, or a trip not started yet: the group side is the useful one.
            if model.inGroup || !model.tripUnderway { mode = .group }
        }
    }

    // MARK: Un lien

    private var link: some View {
        ScrollView {
            VStack(spacing: EonaSpacing.lg) {
                VStack(spacing: EonaSpacing.sm) {
                    EonaGlowTile(icon: .asset(.share), size: 56, iconSize: 26, radius: EonaRadius.lg)
                    Text("Partager mon trajet")
                        .font(.xrTitle)
                        .foregroundStyle(EonaColor.textPrimary)
                    Text("Quelqu'un suit ta position, ton itinéraire et ton heure d'arrivée, jusqu'à ton arrivée.")
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, EonaSpacing.sm)

                linkState
            }
            .padding(.horizontal, EonaSpacing.lg)
            .padding(.bottom, EonaSpacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var linkState: some View {
        if let share = model.tripShare {
            VStack(alignment: .leading, spacing: EonaSpacing.md) {
                HStack(spacing: EonaSpacing.sm) {
                    Circle()
                        .fill(EonaColor.success)
                        .frame(width: 8, height: 8)
                    Text("Partage en cours")
                        .font(.xrLabel)
                        .foregroundStyle(EonaColor.textPrimary)
                    Spacer(minLength: 0)
                    Text(followers)
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textTertiary)
                }
                Text(share.url.absoluteString)
                    .font(.xrFootnote.monospaced())
                    .foregroundStyle(EonaColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                ShareLink(item: share.url, message: Text("Suis mon trajet sur EONA")) {
                    Text("Envoyer le lien")
                        .font(.xrBodyStrong)
                        .foregroundStyle(EonaColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, EonaSpacing.md)
                        .background(EonaColor.accent, in: .rect(cornerRadius: EonaRadius.md))
                }
                EonaButton(title: "Arrêter le partage", variant: .destructive, fillWidth: true) {
                    Task {
                        await model.stopSharing()
                        onClose()
                    }
                }
                Text("Le lien s'éteint 15 minutes après ton arrivée. Il faut un compte EONA pour l'ouvrir.")
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textTertiary)
            }
            .xrSheetCard()
        } else if !model.tripUnderway {
            VStack(spacing: EonaSpacing.sm) {
                EonaIconView(icon: .symbol(.navigation), size: 22)
                    .foregroundStyle(EonaColor.textTertiary)
                Text("Pas encore en route")
                    .font(.xrLabel)
                    .foregroundStyle(EonaColor.textPrimary)
                Text("Le lien se crée une fois le trajet commencé, quand tu es sur l'itinéraire. Pour partir à plusieurs dès maintenant, passe par « En groupe ».")
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .xrSheetCard()
        } else {
            VStack(spacing: EonaSpacing.md) {
                EonaButton(title: "Créer le lien", loading: model.openingShare, fillWidth: true) {
                    Task { failed = await model.startSharing() == nil }
                }
                if failed {
                    Text("Le lien n'a pas pu être créé. Vérifie ta connexion et réessaie.")
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.danger)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var followers: String {
        switch model.tripShare?.followers ?? 0 {
        case 0: "personne ne suit"
        case 1: "1 personne suit"
        case let count: "\(count) personnes suivent"
        }
    }
}

/// Two sides on one track: the chosen side lies on the accent, the other stays clear.
private struct ShareModePicker: View {
    @Binding var mode: TripShareSheet.Mode
    @Namespace private var track

    var body: some View {
        HStack(spacing: EonaSpacing.xs) {
            ForEach(TripShareSheet.Mode.allCases, id: \.self) { option in
                Button {
                    mode = option
                } label: {
                    HStack(spacing: EonaSpacing.sm) {
                        EonaIconView(icon: option.icon, size: 15)
                        Text(option.label)
                            .font(.xrLabel)
                    }
                    .foregroundStyle(mode == option ? EonaColor.onAccent : EonaColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, EonaSpacing.sm + 2)
                    .background {
                        if mode == option {
                            Capsule()
                                .fill(EonaColor.accent)
                                .matchedGeometryEffect(id: "mode", in: track)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
        .padding(EonaSpacing.xs)
        // On the sheet's glass, a pale track: no glass laid on glass.
        .background(EonaColor.surface.opacity(0.5), in: .capsule)
        .overlay { Capsule().strokeBorder(EonaColor.border, lineWidth: 1) }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: mode)
    }
}
