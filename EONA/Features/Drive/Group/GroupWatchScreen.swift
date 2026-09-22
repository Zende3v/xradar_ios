import MapKit
import SwiftUI
import EonaCore
import EonaData

/// The other side of a group link: someone watches the trip without driving in it.
///
/// What this screen can show is decided on the other side. A participant who does not share, or
/// who is not visible from the link, is simply absent: no name in the list, no dot on the map.
/// Nothing about a past trip is shown, ever — only what is happening.
struct GroupWatchScreen: View {
    let services: AppServices
    let linkToken: String
    let onClose: () -> Void

    @State private var group: ObservedGroup?
    @State private var over = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var placed = false

    var body: some View {
        ZStack(alignment: .top) {
            map
                .ignoresSafeArea()

            header
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
        .task(id: linkToken) { await watch() }
    }

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
            ForEach(Array((group?.members ?? []).enumerated()), id: \.element.id) { index, member in
                if member.route.count >= 2 {
                    MapPolyline(coordinates: member.route.map(GroupCamera.coordinate))
                        .stroke(GroupPalette.color(index), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            ForEach(Array((group?.members ?? []).enumerated()), id: \.element.id) { index, member in
                if let position = member.position {
                    Annotation(member.name, coordinate: GroupCamera.coordinate(position)) {
                        GroupDot(name: member.name, color: GroupPalette.color(index), bearing: member.bearing, faded: !member.online)
                    }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

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
            EonaIconButton(icon: .symbol(.close), label: "Fermer", size: 40) { onClose() }
        }
        .padding(EonaSpacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: EonaRadius.lg))
    }

    private var subtitle: String {
        guard let group else { return over ? "Ce partage est terminé." : "En attente du groupe…" }
        if group.isOver { return "Trajet terminé" }
        let count = group.members.count
        return count == 1 ? "1 participant partage sa position" : "\(count) participants partagent leur position"
    }

    @ViewBuilder
    private var bottom: some View {
        if let group, !group.members.isEmpty || !group.ranking.isEmpty {
            VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                if group.isOver {
                    GroupRankingView(entries: group.ranking)
                } else {
                    ForEach(Array(group.members.enumerated()), id: \.element.id) { index, member in
                        GroupMemberRow(member: member, color: GroupPalette.color(index))
                    }
                }
            }
            .padding(EonaSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: EonaRadius.lg))
        }
    }

    /// Asks again while the screen is open, at the pace the drivers move on the map.
    private func watch() async {
        let api = TripGroupAPI(client: services.client)
        while !Task.isCancelled {
            let seen = await api.watch(linkToken, token: services.account.token)
            guard let seen else {
                over = true
                return
            }
            group = seen
            place(seen)
            if seen.isOver {
                // Over: the ranking stays on screen, and nothing more is asked for.
                over = true
                return
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func place(_ seen: ObservedGroup) {
        guard !placed else { return }
        var points = seen.members.compactMap(\.position)
        if let destination = seen.destination { points.append(destination) }
        guard let fitted = GroupCamera.fit(points) else { return }
        camera = fitted
        placed = true
    }
}
