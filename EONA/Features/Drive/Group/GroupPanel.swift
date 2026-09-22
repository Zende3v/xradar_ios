import SwiftUI
import UIKit
import EonaCore
import EonaData

/// The group, from the outside: open one, join one with a code, decide what leaves the phone,
/// hand out the link that lets someone watch, and step out.
///
/// What is shared is said plainly here — who shares and who does not is written in the list, for
/// everybody, mine included.
struct GroupPanel: View {
    let model: DriveModel
    /// Set when the caller can show the group's map; the button is hidden otherwise.
    var onOpenMap: (() -> Void)?

    @State private var code = ""
    @State private var message: String?
    @State private var confirmLeave = false

    private var group: TripGroup? { model.group }

    var body: some View {
        Form {
            if let group {
                inside(group)
            } else {
                outside
            }
        }
        .scrollContentBackground(.hidden)
        .background(EonaColor.canvas)
        .task { await model.refreshGroup() }
        .confirmationDialog(
            group?.isHost == true ? "Annuler le trajet du groupe ?" : "Quitter le groupe ?",
            isPresented: $confirmLeave,
            titleVisibility: .visible
        ) {
            Button(group?.isHost == true ? "Annuler pour tous" : "Quitter", role: .destructive) {
                let host = group?.isHost == true
                Task {
                    if host { await model.cancelGroup() } else { await model.leaveGroup() }
                }
            }
            Button("Continuer le trajet", role: .cancel) {}
        }
    }

    // MARK: Sans groupe

    @ViewBuilder
    private var outside: some View {
        Section {
            EonaButton(title: "Créer un groupe", loading: model.groupBusy, fillWidth: true) {
                Task {
                    if await model.createGroup() == nil {
                        message = model.hasDestination
                            ? "Création impossible — vérifie ta connexion."
                            : "Choisis d'abord une destination : c'est elle que le groupe partage."
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text("Partir à plusieurs")
        } footer: {
            Text("Jusqu'à cinq conducteurs vers la même adresse. Chacun part d'où il veut et suit son propre itinéraire.")
        }

        Section {
            TextField("Code du groupe", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.xrBodyStrong.monospaced())
            EonaButton(title: "Rejoindre", variant: .secondary, loading: model.groupBusy, fillWidth: true) {
                Task {
                    if await model.joinGroup(code: code.trimmingCharacters(in: .whitespaces)) == nil {
                        message = "Code inconnu, groupe complet ou terminé."
                    } else {
                        code = ""
                        message = nil
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text("Rejoindre un groupe")
        } footer: {
            Text("La destination du groupe devient la tienne. Ton itinéraire, lui, part de là où tu es.")
        }

        if let message {
            Section {
                Text(message)
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.danger)
            }
        }
    }

    // MARK: Dans un groupe

    @ViewBuilder
    private func inside(_ group: TripGroup) -> some View {
        Section {
            LabeledContent("Code", value: group.code)
            LabeledContent("Destination", value: group.toLabel ?? "—")
            LabeledContent("Participants", value: "\(group.members.count) / \(group.maxMembers)")
            Button("Copier le code") {
                UIPasteboard.general.string = group.code
                message = "Code copié."
            }
            if let onOpenMap {
                Button("Voir la carte du groupe") { onOpenMap() }
            }
        } header: {
            Text("Le groupe")
        } footer: {
            Text("Donne ce code aux autres conducteurs : ils le saisissent dans « Rejoindre un groupe ».")
        }

        Section {
            Toggle("Partager ma position et ma vitesse", isOn: Binding(
                get: { group.sharing },
                set: { on in Task { await model.setGroupSharing(on) } }
            ))
            Toggle("Visible depuis le lien de partage", isOn: Binding(
                get: { group.observable },
                set: { on in Task { await model.setGroupObservable(on) } }
            ))
            .disabled(!group.sharing)
        } header: {
            Text("Ce que je partage")
        } footer: {
            Text("Coupé, personne ne voit plus ni ma position, ni ma vitesse, ni mon avancement — ni les participants, ni le lien. Je reste dans le groupe, marqué comme ne partageant pas.")
        }

        Section("Participants") {
            ForEach(Array(group.members.enumerated()), id: \.element.id) { index, member in
                GroupMemberRow(member: member, color: GroupPalette.color(index))
            }
        }

        if group.isHost {
            Section {
                if let link = group.link {
                    Text(link.url.absoluteString)
                        .font(.xrFootnote.monospaced())
                        .foregroundStyle(EonaColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    ShareLink(item: link.url, message: Text("Suis notre trajet en groupe sur EONA")) {
                        Text("Envoyer le lien")
                            .font(.xrBodyStrong)
                            .foregroundStyle(EonaColor.accent)
                    }
                    Text(link.observers == 1 ? "1 personne regarde." : "\(link.observers) personnes regardent.")
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textTertiary)
                    Button("Révoquer le lien", role: .destructive) {
                        Task { await model.setGroupLink(open: false) }
                    }
                } else {
                    EonaButton(title: "Créer un lien à partager", variant: .secondary, loading: model.groupBusy, fillWidth: true) {
                        Task { await model.setGroupLink(open: true) }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } header: {
                Text("Observer sans conduire")
            } footer: {
                Text("Qui ouvre ce lien voit la carte, l'avancement, le tracé et la vitesse des participants qui ont accepté de les partager. Rien d'autre. Le lien se révoque à tout moment, et meurt avec le trajet.")
            }
        }

        Section {
            Button(group.isHost ? "Annuler le trajet du groupe" : "Quitter le groupe", role: .destructive) {
                confirmLeave = true
            }
            if let message {
                Text(message)
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textSecondary)
            }
        } footer: {
            Text(group.isHost
                 ? "Le trajet s'arrête pour tout le monde et le lien cesse de fonctionner."
                 : "Tu sors du groupe ; ton trajet continue normalement.")
        }
    }
}

/// The same panel, on its own, opened from the group's map.
struct GroupPanelSheet: View {
    let model: DriveModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            GroupPanel(model: model)
                .navigationTitle("Trajet en groupe")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer") { onClose() }
                    }
                }
        }
    }
}
