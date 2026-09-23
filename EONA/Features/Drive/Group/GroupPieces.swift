import MapKit
import SwiftUI
import EonaCore
import EonaData

/// The small pieces the three group screens share: the colour a driver is drawn in, their dot on
/// the map, their line in the list, and the ranking read at the end.

/// One colour per driver, in the order they joined. Five of them, as a group holds five.
enum GroupPalette {
    static let colors: [Color] = [
        Color(red: 0.17, green: 0.83, blue: 0.87),
        Color(red: 0.98, green: 0.74, blue: 0.29),
        Color(red: 0.55, green: 0.78, blue: 0.35),
        Color(red: 0.95, green: 0.45, blue: 0.55),
        Color(red: 0.62, green: 0.56, blue: 0.95),
    ]

    static func color(_ index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}

/// A driver on the map: their colour, their initial, and their heading when it is known.
struct GroupDot: View {
    let name: String
    let color: Color
    let bearing: Double?
    let faded: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 26, height: 26)
                .overlay { Circle().strokeBorder(EonaColor.onAccent, lineWidth: 3) }
                .shadow(radius: 4)
            Text(initial)
                .font(.xrFootnote.weight(.bold))
                .foregroundStyle(EonaColor.onAccent)
            if let bearing {
                EonaIconView(icon: .symbol(.chevronUp), size: 12)
                    .foregroundStyle(color)
                    .offset(y: -22)
                    .rotationEffect(.degrees(bearing), anchor: .init(x: 0.5, y: 1.6))
            }
        }
        .opacity(faded ? 0.45 : 1)
    }

    private var initial: String {
        String(name.prefix(1)).uppercased()
    }
}

/// One driver in the list under the map: where they are in their own trip, and how fast.
struct GroupMemberRow: View {
    let member: GroupMember
    let color: Color
    /// Set when this line can be tapped to follow that driver closely.
    var selected = false
    /// The line opens their card: a chevron says so.
    var showsCard = false

    var body: some View {
        HStack(spacing: EonaSpacing.md) {
            GroupAvatar(url: member.avatarURL, name: member.name, color: color, size: 34)
                .opacity(!member.online && member.sharing ? 0.45 : 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: EonaSpacing.xs) {
                    Text(member.name)
                        .font(.xrBodyStrong)
                        .foregroundStyle(EonaColor.textPrimary)
                        .lineLimit(1)
                    if !member.sharing {
                        EonaIconView(icon: .symbol(.eyeSlash), size: 13)
                            .foregroundStyle(EonaColor.textTertiary)
                    }
                }
                Text(member.detailLabel)
                    .font(.xrFootnote)
                    .foregroundStyle(member.online || !member.sharing ? EonaColor.textSecondary : EonaColor.warning)
                    .lineLimit(1)
                if member.sharing && member.state != .arrived {
                    ProgressView(value: member.progress)
                        .tint(color)
                        .scaleEffect(x: 1, y: 0.6, anchor: .center)
                }
            }
            Spacer(minLength: 0)
            if selected {
                EonaIconView(icon: .symbol(.check), size: 16)
                    .foregroundStyle(EonaColor.accent)
            }
            if showsCard {
                EonaIconView(icon: .symbol(.chevronRight), size: 13)
                    .foregroundStyle(EonaColor.textTertiary)
            }
        }
        .padding(.vertical, EonaSpacing.xs)
        .contentShape(.rect)
    }
}

/// The arrival ranking, frozen when the trip ended: who got there, in which order, in how long.
struct GroupRankingView: View {
    let entries: [GroupRankEntry]
    /// The line to point out as mine, when there is one.
    var mineId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            Text("Classement")
                .font(.xrHeadline)
                .foregroundStyle(EonaColor.textPrimary)
            ForEach(entries) { entry in
                HStack(spacing: EonaSpacing.md) {
                    Text(entry.rankLabel)
                        .font(.xrNumeric)
                        .foregroundStyle(entry.rank == 1 ? EonaColor.accent : EonaColor.textSecondary)
                        .frame(width: 34, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.id == mineId ? "\(entry.name) (moi)" : entry.name)
                            .font(.xrBody)
                            .foregroundStyle(EonaColor.textPrimary)
                        Text(entry.rank == nil ? entry.state.label : entry.timeLabel)
                            .font(.xrFootnote)
                            .foregroundStyle(EonaColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Where the map should look to hold everything it has to show.
enum GroupCamera {
    static func fit(_ points: [GeoPoint]) -> MapCameraPosition? {
        guard !points.isEmpty else { return nil }
        let lats = points.map(\.lat)
        let lons = points.map(\.lon)
        let center = CLLocationCoordinate2D(
            latitude: ((lats.min() ?? 0) + (lats.max() ?? 0)) / 2,
            longitude: ((lons.min() ?? 0) + (lons.max() ?? 0)) / 2
        )
        // A quarter more than the spread, and never so tight that one driver fills the screen.
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.05, ((lats.max() ?? 0) - (lats.min() ?? 0)) * 1.4),
            longitudeDelta: max(0.05, ((lons.max() ?? 0) - (lons.min() ?? 0)) * 1.4)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    static func coordinate(_ point: GeoPoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
    }
}
