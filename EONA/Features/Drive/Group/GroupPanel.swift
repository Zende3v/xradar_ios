import SwiftUI
import UIKit
import EonaCore
import EonaData

/// "Trajet en groupe", from the outside: open one on the chosen destination, join one with its
/// code, decide what leaves the phone, hand out the link, and step out.
///
/// Who shares and who does not is always written — for everybody, mine included.
struct GroupPanel: View {
    let model: DriveModel

    @State private var code = ""
    @State private var message: String?
    @State private var confirmLeave = false
    @State private var copied = false
    /// A participant's card, opened from their line.
    @State private var card: MemberCardTarget?

    private var group: TripGroup? { model.group }

    var body: some View {
        ScrollView {
            VStack(spacing: EonaSpacing.lg) {
                if let group, !group.isCancelled {
                    inside(group)
                } else {
                    outside
                }
            }
            .padding(.horizontal, EonaSpacing.lg)
            .padding(.top, EonaSpacing.xs)
            .padding(.bottom, EonaSpacing.xxl)
            .animation(.easeInOut(duration: 0.25), value: group?.id)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .task { await model.refreshGroup() }
        .sheet(item: $card) { target in
            MemberCardSheet(model: model, target: target)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(leaveTitle, isPresented: $confirmLeave, titleVisibility: .visible) {
            if group?.isHost == true {
                Button("Annuler pour tout le monde", role: .destructive) {
                    Task { await model.cancelGroup() }
                }
                if (group?.members.filter(\.isPresent).count ?? 0) > 1 {
                    Button("Quitter et laisser le groupe continuer") {
                        Task { await model.leaveGroup() }
                    }
                }
            } else {
                Button("Quitter le groupe", role: .destructive) {
                    Task { await model.leaveGroup() }
                }
            }
            Button("Rester", role: .cancel) {}
        } message: {
            Text(group?.isHost == true
                 ? "Annuler arrête le trajet commun pour tous. En quittant, le groupe continue et un autre participant le mène."
                 : "Ton trajet continue normalement ; les autres ne te voient plus.")
        }
    }

    private var leaveTitle: String {
        group?.isHost == true ? "Quitter le trajet en groupe ?" : "Quitter le groupe ?"
    }

    // MARK: Sans groupe

    @ViewBuilder
    private var outside: some View {
        VStack(spacing: EonaSpacing.sm) {
            EonaGlowTile(icon: .symbol(.people), size: 56, iconSize: 26, radius: EonaRadius.lg)
            Text("Rouler ensemble")
                .font(.xrTitle)
                .foregroundStyle(EonaColor.textPrimary)
            Text("Jusqu'à cinq conducteurs vers la même adresse. Chacun part d'où il veut, suit sa route, et voit les autres avancer.")
                .font(.xrFootnote)
                .foregroundStyle(EonaColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, EonaSpacing.sm)

        // Créer : la destination choisie devient celle du groupe.
        VStack(alignment: .leading, spacing: EonaSpacing.md) {
            sectionTitle("Créer un groupe")
            if let name = model.destinationName {
                HStack(spacing: EonaSpacing.md) {
                    EonaIconView(icon: .symbol(.flag), size: 16)
                        .foregroundStyle(EonaColor.accent)
                        .frame(width: 32, height: 32)
                        .background(EonaColor.accent.opacity(0.14), in: .rect(cornerRadius: EonaRadius.sm))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Destination commune")
                            .font(.xrCaption)
                            .foregroundStyle(EonaColor.textTertiary)
                        Text(name)
                            .font(.xrBodyStrong)
                            .foregroundStyle(EonaColor.textPrimary)
                            .lineLimit(2)
                    }
                }
                EonaButton(title: "Créer le groupe", loading: model.groupBusy, fillWidth: true) {
                    Task {
                        message = await model.createGroup() == nil ? "Création impossible — vérifie ta connexion." : nil
                    }
                }
            } else {
                Text("Choisis d'abord une destination : c'est elle que le groupe partagera.")
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .xrSheetCard()

        // Rejoindre : six caractères, lisibles à voix haute.
        VStack(alignment: .leading, spacing: EonaSpacing.md) {
            sectionTitle("Rejoindre avec un code")
            GroupCodeField(code: $code)
            EonaButton(title: "Rejoindre", variant: .secondary, loading: model.groupBusy, fillWidth: true) {
                Task {
                    if await model.joinGroup(code: code) == nil {
                        message = "Code inconnu, groupe complet ou trajet terminé."
                    } else {
                        code = ""
                        message = nil
                    }
                }
            }
            .disabled(code.count < GroupCodeField.length)
            Text("La destination du groupe devient la tienne ; ton itinéraire part de là où tu es.")
                .font(.xrFootnote)
                .foregroundStyle(EonaColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .xrSheetCard()

        if let message {
            Text(message)
                .font(.xrFootnote)
                .foregroundStyle(EonaColor.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Dans un groupe

    @ViewBuilder
    private func inside(_ group: TripGroup) -> some View {
        header(group)

        participants(group)

        if !group.isOver {
            visibility(group)
            if group.isHost { watchLink(group) }
            EonaButton(title: group.isHost ? "Quitter ou annuler le trajet" : "Quitter le groupe", variant: .ghost, fillWidth: true) {
                confirmLeave = true
            }
        } else {
            VStack(alignment: .leading, spacing: EonaSpacing.md) {
                GroupRankingView(entries: group.ranking, mineId: model.myAccountId)
                EonaButton(title: "Terminer", fillWidth: true) { model.dismissGroup() }
            }
            .xrSheetCard()
        }
    }

    /// Where the group goes, its code in large, and the way to hand it out.
    private func header(_ group: TripGroup) -> some View {
        VStack(alignment: .leading, spacing: EonaSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.isOver ? "Trajet terminé" : "Destination commune")
                        .font(.xrCaption)
                        .foregroundStyle(EonaColor.textTertiary)
                    Text(group.toLabel ?? "Destination du groupe")
                        .font(.xrHeadline)
                        .foregroundStyle(EonaColor.textPrimary)
                        .lineLimit(2)
                }
                Spacer(minLength: EonaSpacing.md)
                EonaBadge(text: "\(group.members.filter(\.isPresent).count)/\(group.maxMembers)")
            }

            if !group.isOver {
                HStack(spacing: EonaSpacing.xs) {
                    ForEach(Array(group.code.enumerated()), id: \.offset) { _, letter in
                        Text(String(letter))
                            .font(.system(size: 26, weight: .semibold, design: .monospaced))
                            .foregroundStyle(EonaColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(EonaColor.surface.opacity(0.55), in: .rect(cornerRadius: EonaRadius.sm))
                            .overlay {
                                RoundedRectangle(cornerRadius: EonaRadius.sm).strokeBorder(EonaColor.border, lineWidth: 1)
                            }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Code du groupe : \(group.code.map(String.init).joined(separator: " "))")

                HStack(spacing: EonaSpacing.sm) {
                    EonaButton(title: copied ? "Copié" : "Copier", variant: .secondary, fillWidth: true) {
                        UIPasteboard.general.string = group.code
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    }
                    ShareLink(item: invitation(group)) {
                        Text("Inviter")
                            .font(.xrBodyStrong)
                            .foregroundStyle(EonaColor.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, EonaSpacing.md)
                            .background(EonaColor.accent, in: .capsule)
                    }
                }

                if !group.isHost, let host = group.hostName {
                    Text("Mené par \(host)")
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textTertiary)
                }
            }
        }
        .xrSheetCard()
    }

    /// Everyone, with what they share — a closed eye for those who do not.
    private func participants(_ group: TripGroup) -> some View {
        // Those who left are gone from the list; everyone keeps the colour of their place.
        let present = Array(group.members.enumerated()).filter { $0.element.isPresent }
        let free = group.maxMembers - present.count
        return VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            sectionTitle("Participants")
            ForEach(present, id: \.element.id) { index, member in
                // A tap on the line: their card.
                Button {
                    card = MemberCardTarget(id: member.id, colorIndex: index)
                } label: {
                    GroupMemberRow(member: member, color: GroupPalette.color(index), showsCard: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ouvrir sa fiche")
                if member.id != present.last?.element.id {
                    Divider().overlay(EonaColor.separator)
                }
            }
            if free > 0, !group.isOver {
                Text("Encore \(free) place\(free > 1 ? "s" : "")")
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textTertiary)
                    .padding(.top, EonaSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .xrSheetCard()
    }

    /// What leaves my phone. Both switch at once and stay switched.
    private func visibility(_ group: TripGroup) -> some View {
        // Once the trip is launched the switches speak for themselves: only the warning that
        // nothing is shared stays.
        let launched = model.hasDestination
        return VStack(alignment: .leading, spacing: EonaSpacing.md) {
            sectionTitle("Ce que je partage")
            switchRow(
                title: "Ma position et ma vitesse",
                detail: model.groupSharing
                    ? (launched ? nil : "Visibles par le groupe dès que tu es en route.")
                    : "Personne ne voit ni ta position, ni ta vitesse, ni ton avancement.",
                isOn: Binding(get: { model.groupSharing }, set: { on in Task { await model.setGroupSharing(on) } })
            )
            Divider().overlay(EonaColor.separator)
            switchRow(
                title: "Visible depuis le lien",
                detail: launched ? nil : "Hors du lien d'observation, tu restes visible pour le groupe.",
                isOn: Binding(get: { model.groupObservable }, set: { on in Task { await model.setGroupObservable(on) } })
            )
            .disabled(!model.groupSharing)
            .opacity(model.groupSharing ? 1 : 0.45)
        }
        .xrSheetCard()
    }

    private func switchRow(title: String, detail: String?, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.xrBodyStrong)
                    .foregroundStyle(EonaColor.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(EonaColor.accent)
    }

    /// The host's link for people who watch without driving.
    private func watchLink(_ group: TripGroup) -> some View {
        VStack(alignment: .leading, spacing: EonaSpacing.md) {
            sectionTitle("Observer sans conduire")
            if let link = group.link {
                HStack(spacing: EonaSpacing.sm) {
                    Circle().fill(EonaColor.success).frame(width: 8, height: 8)
                    Text(link.observers == 0
                         ? "Lien actif · personne ne regarde"
                         : "Lien actif · \(link.observers) \(link.observers == 1 ? "personne regarde" : "personnes regardent")")
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textSecondary)
                }
                HStack(spacing: EonaSpacing.sm) {
                    ShareLink(item: link.url, message: Text("Suis notre trajet en groupe sur EONA")) {
                        Text("Envoyer")
                            .font(.xrBodyStrong)
                            .foregroundStyle(EonaColor.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, EonaSpacing.md)
                            .background(EonaColor.accent, in: .capsule)
                    }
                    EonaButton(title: "Révoquer", variant: .destructive, fillWidth: true) {
                        Task { await model.setGroupLink(open: false) }
                    }
                }
            } else {
                EonaButton(title: "Créer un lien", variant: .secondary, loading: model.groupBusy, fillWidth: true) {
                    Task { await model.setGroupLink(open: true) }
                }
            }
            Text("Qui l'ouvre voit la carte, l'avancement, le tracé et la vitesse des seuls participants qui l'acceptent. Il meurt avec le trajet.")
                .font(.xrFootnote)
                .foregroundStyle(EonaColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .xrSheetCard()
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.xrCaption)
            .tracking(0.6)
            .foregroundStyle(EonaColor.textTertiary)
    }

    private func invitation(_ group: TripGroup) -> String {
        let place = group.toLabel.map { " vers \($0)" } ?? ""
        return "Rejoins mon trajet EONA\(place) : ouvre EONA, « En groupe », code \(group.code)."
    }
}

/// Six boxes for six characters. The real field is invisible over them: typing, pasting and
/// deleting behave as in any text field, uppercase and nothing that could be misread.
struct GroupCodeField: View {
    static let length = 6
    @Binding var code: String
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            HStack(spacing: EonaSpacing.xs) {
                ForEach(0..<Self.length, id: \.self) { index in
                    let letters = Array(code)
                    let current = index == min(letters.count, Self.length - 1) && focused
                    Text(index < letters.count ? String(letters[index]) : "")
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundStyle(EonaColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(EonaColor.surface.opacity(0.55), in: .rect(cornerRadius: EonaRadius.sm))
                        .overlay {
                            RoundedRectangle(cornerRadius: EonaRadius.sm)
                                .strokeBorder(current ? EonaColor.accent : EonaColor.border, lineWidth: current ? 2 : 1)
                        }
                }
            }
            TextField("", text: $code)
                .focused($focused)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .textContentType(.oneTimeCode)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .accessibilityLabel("Code du groupe")
        }
        .frame(height: 50)
        .onTapGesture { focused = true }
        .onChange(of: code) { _, typed in
            let clean = String(typed.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(Self.length))
            if clean != typed { code = clean }
        }
    }
}
