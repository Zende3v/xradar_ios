import SwiftUI
import EonaCore
import EonaData

/// Sharing the trip, two ways: a link somebody follows, or a group of drivers heading for the
/// same address, each on their own road.
///
/// The link is opened when its side appears, sent from here, and dies at the arrival. The driver
/// sees how many people follow — never who.
struct TripShareSheet: View {
    let model: DriveModel
    /// Called when the driver asks for the group's map: the sheet closes and the map opens.
    var onOpenGroupMap: (() -> Void)?
    let onClose: () -> Void

    /// Which side is shown; a group already running opens on its own.
    @State private var mode: Mode = .link
    @State private var failed = false

    enum Mode: String, CaseIterable {
        case link
        case group

        var label: String { self == .link ? "Un lien" : "En groupe" }
    }

    var body: some View {
        VStack(spacing: EonaSpacing.md) {
            Capsule()
                .fill(EonaColor.borderStrong)
                .frame(width: 40, height: 5)
                .padding(.top, EonaSpacing.sm)

            Picker("Partage", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, EonaSpacing.lg)

            switch mode {
            case .link: link
            case .group: GroupPanel(model: model, onOpenMap: onOpenGroupMap)
            }
        }
        .padding(.bottom, EonaSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(EonaColor.canvas)
        .task {
            if model.group != nil { mode = .group }
        }
    }

    // MARK: Un lien

    @ViewBuilder
    private var link: some View {
        VStack(spacing: EonaSpacing.lg) {
            EonaIconView(icon: .asset(.share), size: 44)
                .foregroundStyle(EonaColor.accent)

            VStack(spacing: EonaSpacing.xs) {
                Text("Partager mon trajet")
                    .font(.xrTitle)
                    .foregroundStyle(EonaColor.textPrimary)
                Text(subtitle)
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let share = model.tripShare {
                Text(share.url.absoluteString)
                    .font(.xrFootnote.monospaced())
                    .foregroundStyle(EonaColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(EonaSpacing.md)
                    .frame(maxWidth: .infinity)
                    .background(EonaColor.surface, in: .rect(cornerRadius: EonaRadius.md))
                    .textSelection(.enabled)

                ShareLink(item: share.url, message: Text("Suis mon trajet sur EONA")) {
                    Text("Envoyer le lien")
                        .font(.xrBodyStrong)
                        .foregroundStyle(EonaColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, EonaSpacing.md)
                        .background(EonaColor.accent, in: .rect(cornerRadius: EonaRadius.md))
                }

                EonaButton(title: "Arrêter le partage", variant: .secondary, fillWidth: true) {
                    Task {
                        await model.stopSharing()
                        onClose()
                    }
                }

                Text(followers)
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textTertiary)
            } else if failed {
                Text("Le lien n'a pas pu être créé. Vérifie ta connexion et réessaie.")
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.danger)
                    .multilineTextAlignment(.center)
                EonaButton(title: "Réessayer", fillWidth: true) {
                    Task { await open() }
                }
            } else {
                ProgressView()
                    .tint(EonaColor.accent)
                    .padding(.vertical, EonaSpacing.lg)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, EonaSpacing.lg)
        .task {
            if model.tripShare == nil { await open() }
        }
    }

    private var subtitle: String {
        model.tripShare == nil
            ? "Un lien qui montre où tu es, ton itinéraire et ton heure d'arrivée."
            : "Le lien s'éteint 15 minutes après ton arrivée. Il faut un compte EONA pour l'ouvrir."
    }

    private var followers: String {
        switch model.tripShare?.followers ?? 0 {
        case 0: "Personne ne suit encore ton trajet."
        case 1: "1 personne suit ton trajet."
        case let count: "\(count) personnes suivent ton trajet."
        }
    }

    private func open() async {
        failed = await model.startSharing() == nil
    }
}
