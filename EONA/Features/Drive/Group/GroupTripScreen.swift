import MapKit
import SwiftUI
import EonaCore
import EonaData

/// "Trajet en groupe", seen from inside: everyone on the same map, each on their own road to the
/// same address. Two views — the group, or one participant followed closely — and, at the end,
/// the ranking.
///
/// Only the drivers who agreed to share give a position, a speed and a progress. The others are
/// in the list, named, and nothing more.
struct GroupTripScreen: View {
    let services: AppServices
    let model: DriveModel
    let onClose: () -> Void

    /// nil = the group view; otherwise the participant being followed.
    @State private var focused: String?
    @State private var camera: MapCameraPosition = .automatic
    @State private var panel = false
    @State private var placed = false

    private var group: TripGroup? { model.group }

    var body: some View {
        ZStack(alignment: .top) {
            map
                .ignoresSafeArea()

            VStack(spacing: EonaSpacing.sm) {
                header
                if let group, !group.isOver {
                    viewPicker(group)
                }
            }
            .padding(.horizontal, EonaSpacing.lg)
            .padding(.top, EonaSpacing.sm)

            VStack {
                Spacer(minLength: 0)
                bottom
                    .padding(.horizontal, EonaSpacing.lg)
                    .padding(.bottom, EonaSpacing.lg)
            }
        }
        .background(EonaColor.canvas)
        .task { await model.refreshGroup() }
        .onChange(of: focused) { _, id in
            model.follow(member: id)
            placed = false
        }
        .onChange(of: model.group?.members.count) { _, _ in place() }
        .onChange(of: drawn.compactMap(\.position).count) { _, _ in place() }
        .onDisappear { model.follow(member: nil) }
        .sheet(isPresented: $panel) {
            GroupPanelSheet(model: model) { panel = false }
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Carte

    @ViewBuilder
    private var map: some View {
        Map(position: $camera) {
            if let destination = group?.destination {
                Annotation(group?.toLabel ?? "Arrivée", coordinate: GroupCamera.coordinate(destination)) {
                    EonaIconView(icon: .symbol(.flag), size: 22)
                        .foregroundStyle(EonaColor.textPrimary)
                        .padding(EonaSpacing.xs)
                        .background(EonaColor.surface, in: .circle)
                }
            }
            // My own road, always drawn; a participant's road only in their view.
            if focused == nil, model.myRoute.count >= 2 {
                MapPolyline(coordinates: model.myRoute.map(GroupCamera.coordinate))
                    .stroke(EonaColor.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if let followed = model.followedMember, followed.route.count >= 2 {
                MapPolyline(coordinates: followed.route.map(GroupCamera.coordinate))
                    .stroke(color(of: followed.id), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            ForEach(drawn) { member in
                if let position = member.position {
                    Annotation(member.name, coordinate: GroupCamera.coordinate(position)) {
                        GroupDot(
                            name: member.name,
                            color: color(of: member.id),
                            bearing: member.bearing,
                            faded: !member.online
                        )
                    }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    /// The drivers to place on the map: everyone who shares, or the one being followed.
    private var drawn: [GroupMember] {
        guard let group else { return [] }
        if let focused {
            return group.members.filter { $0.id == focused && $0.sharing }
        }
        return group.members.filter { $0.sharing && $0.position != nil }
    }

    /// The map is framed once, and again when the group changes shape; the driver pans freely.
    private func place() {
        guard !placed else { return }
        var points = drawn.compactMap(\.position)
        if let destination = group?.destination { points.append(destination) }
        guard let fitted = GroupCamera.fit(points) else { return }
        camera = fitted
        placed = true
    }

    // MARK: Bandeaux

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group?.toLabel ?? "Trajet en groupe")
                    .font(.xrHeadline)
                    .foregroundStyle(EonaColor.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textSecondary)
            }
            Spacer(minLength: EonaSpacing.md)
            EonaIconButton(icon: .symbol(.info), label: "Réglages du groupe", size: 40) { panel = true }
            EonaIconButton(icon: .symbol(.close), label: "Fermer", size: 40) { onClose() }
        }
        .padding(EonaSpacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: EonaRadius.lg))
    }

    private var subtitle: String {
        guard let group else { return "Aucun groupe en cours" }
        if group.isOver { return "Trajet terminé" }
        let sharing = group.members.filter(\.sharing).count
        return "\(group.members.count) participants · \(sharing) partagent leur position"
    }

    /// Group view, or one participant — only those who share can be followed.
    private func viewPicker(_ group: TripGroup) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: EonaSpacing.sm) {
                chip(title: "Groupe", color: EonaColor.accent, on: focused == nil) { focused = nil }
                ForEach(group.members.filter(\.sharing)) { member in
                    chip(title: member.name, color: color(of: member.id), on: focused == member.id) {
                        focused = focused == member.id ? nil : member.id
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(title: String, color: Color, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.xrCallout)
                .foregroundStyle(on ? EonaColor.onAccent : EonaColor.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, EonaSpacing.md)
                .padding(.vertical, EonaSpacing.xs)
                .background(on ? color : EonaColor.surface, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var bottom: some View {
        if let group {
            VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                if group.isOver {
                    GroupRankingView(entries: group.ranking, mineId: myId)
                    EonaButton(title: "Terminer", fillWidth: true) {
                        model.dismissGroup()
                        onClose()
                    }
                } else if let focused, let member = model.followedMember ?? group.members.first(where: { $0.id == focused }) {
                    followedCard(member)
                } else {
                    ForEach(group.members) { member in
                        Button {
                            if member.sharing { self.focused = member.id }
                        } label: {
                            GroupMemberRow(member: member, color: color(of: member.id))
                        }
                        .buttonStyle(.plain)
                        .disabled(!member.sharing)
                    }
                }
            }
            .padding(EonaSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: EonaRadius.lg))
        }
    }

    /// The followed participant: their progress, their speed, their arrival. Nothing else.
    private func followedCard(_ member: GroupMember) -> some View {
        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            HStack(spacing: EonaSpacing.md) {
                GroupDot(name: member.name, color: color(of: member.id), bearing: nil, faded: !member.online)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.xrHeadline)
                        .foregroundStyle(EonaColor.textPrimary)
                    Text(member.detailLabel)
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textSecondary)
                }
                Spacer(minLength: 0)
                if let speed = member.speedKmh {
                    VStack(spacing: 0) {
                        Text("\(speed)")
                            .font(.xrNumeric)
                            .foregroundStyle(EonaColor.textPrimary)
                        Text("km/h")
                            .font(.xrFootnote)
                            .foregroundStyle(EonaColor.textTertiary)
                    }
                }
            }
            ProgressView(value: member.progress)
                .tint(color(of: member.id))
            if let eta = member.etaAt, member.state != .arrived {
                Text("Arrivée estimée \(eta.formatted(date: .omitted, time: .shortened))")
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textSecondary)
            }
            EonaButton(title: "Revenir au groupe", variant: .secondary, fillWidth: true) { focused = nil }
        }
    }

    private var myId: String? { services.account.account?.id }

    /// A driver keeps the same colour throughout, taken from where they stand in the group.
    private func color(of id: String) -> Color {
        let index = group?.members.firstIndex(where: { $0.id == id }) ?? 0
        return GroupPalette.color(index)
    }
}
