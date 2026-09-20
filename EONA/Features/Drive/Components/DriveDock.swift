import SwiftUI
import EonaCore
import EonaData

/// "E3", the drop-up dock at the bottom of the HUD: the live speed with the limit that applies
/// here, the red-light timer, the trip figures while navigating, and the options one drag away.
/// It floats over the map in Liquid Glass; pulled up, it takes up to four fifths of the screen.
struct DriveDock: View {
    let speedKmh: Int
    let limitKmh: Int?
    let status: SpeedStatus?
    let searching: Bool
    let trip: TripInfo?
    /// Height the dock may reach when pulled all the way up.
    let maxHeight: CGFloat
    let preferences: PreferencesStore
    /// Tap on the limit sign: propose a new limit (nil = not tappable).
    var onLimitClick: (() -> Void)?
    /// True as soon as the dock is pulled open, so the HUD can clear the way.
    var onOpenChange: (Bool) -> Void = { _ in }

    /// 0 at rest, 1 pulled all the way up. Kept here: a drag redraws the dock, not the whole HUD.
    @State private var progress: CGFloat = 0
    @State private var dragStart: CGFloat?

    /// Past this much opening, the dock owns the screen and the map controls step aside.
    static let openThreshold: CGFloat = 0.12
    /// Exactly the handle and the cards (and the trip line when there is one).
    private static let collapsedPlain: CGFloat = 124
    private static let collapsedWithTrip: CGFloat = 166
    private static let cardHeight: CGFloat = 82
    /// A flick faster than this (pt/s) opens or closes the dock whatever its position.
    private static let flingSpeed: CGFloat = 120

    var body: some View {
        let collapsed = trip != nil ? Self.collapsedWithTrip : Self.collapsedPlain
        let travel = max(max(maxHeight, collapsed) - collapsed, 1)
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                handle
                if let trip {
                    TripLine(trip: trip)
                        .padding(.bottom, EonaSpacing.sm)
                }
                HStack(spacing: EonaSpacing.sm) {
                    // Speed and red light share the width 1.45 to 1, as on Android.
                    GeometryReader { proxy in
                        let width = proxy.size.width - EonaSpacing.sm
                        HStack(spacing: EonaSpacing.sm) {
                            SpeedCard(speedKmh: speedKmh, limitKmh: limitKmh, status: status, searching: searching, onLimitClick: onLimitClick)
                                .frame(width: max(width * 1.45 / 2.45, 0))
                            RedLightCard()
                                .frame(width: max(width / 2.45, 0))
                        }
                    }
                    .frame(height: Self.cardHeight)
                    OptionsCard(open: progress > 0.5) {
                        settle(open: progress < 0.5)
                    }
                }
            }
            .contentShape(.rect)
            .gesture(drag(travel: travel))

            // Always built, only hidden at rest: creating it as the drag starts made the dock stall.
            // A drawer the height of the open dock, uncovered as the dock grows: nothing in it
            // moves or reflows during the drag, and its lists scroll inside their own cards.
            DockOptions(preferences: preferences)
                .padding(.top, EonaSpacing.md)
                .frame(height: travel, alignment: .top)
                .opacity(Double(progress))
                .allowsHitTesting(progress > 0.02)
                .accessibilityHidden(progress <= 0.02)
        }
        .padding(.horizontal, EonaSpacing.md)
        .padding(.bottom, EonaSpacing.md)
        .frame(maxWidth: .infinity)
        .frame(height: collapsed + travel * progress, alignment: .top)
        .clipShape(.rect(cornerRadius: EonaRadius.xxl))
        .glassEffect(.regular, in: .rect(cornerRadius: EonaRadius.xxl))
        .onChange(of: progress > Self.openThreshold) { _, open in
            onOpenChange(open)
        }
    }

    private var handle: some View {
        Capsule()
            .fill(EonaColor.borderStrong)
            .frame(width: 44, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.vertical, EonaSpacing.sm)
            .contentShape(.rect)
            .onTapGesture { settle(open: progress < 0.5) }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(progress > 0.5 ? "Replier les options" : "Déplier les options")
    }

    /// Measured on the screen: the dock grows under the finger, so its own coordinates would
    /// move with it and swallow the drag (only the final flick used to count).
    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStart ?? progress
                if dragStart == nil { dragStart = progress }
                progress = min(max(start - value.translation.height / travel, 0), 1)
            }
            .onEnded { value in
                dragStart = nil
                let velocity = value.velocity.height
                if velocity < -Self.flingSpeed {
                    settle(open: true)
                } else if velocity > Self.flingSpeed {
                    settle(open: false)
                } else {
                    settle(open: progress > 0.4)
                }
            }
    }

    private func settle(open: Bool) {
        withAnimation(.spring(response: 0.31, dampingFraction: 0.85)) {
            progress = open ? 1 : 0
        }
    }
}

/// Trip figures, always in sight: time left, distance left, arrival time.
private struct TripLine: View {
    let trip: TripInfo

    var body: some View {
        HStack(spacing: EonaSpacing.sm) {
            cluster(trip.remainingLabel, "Restantes", EonaColor.accent)
            cluster(trip.distanceLabel, "Distance", EonaColor.textPrimary)
            cluster(trip.arrivalLabel, "Arrivée", EonaColor.textPrimary)
        }
        .padding(.horizontal, EonaSpacing.xs)
    }

    private func cluster(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.xrBodyStrong.monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.xrCaption)
                .foregroundStyle(EonaColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Card 1: the real speed, with the limit that applies right here beside it.
private struct SpeedCard: View {
    let speedKmh: Int
    let limitKmh: Int?
    let status: SpeedStatus?
    let searching: Bool
    let onLimitClick: (() -> Void)?

    var body: some View {
        HStack(spacing: EonaSpacing.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text(searching ? "--" : String(max(speedKmh, 0)))
                    .font(.system(size: 40, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
                    // A fix lands once a second: the digits roll there instead of jumping.
                    .contentTransition(.numericText(value: Double(speedKmh)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(searching ? "Recherche GPS…" : "km/h")
                    .font(.xrCaption)
                    .foregroundStyle(EonaColor.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            sign
        }
        .padding(.horizontal, EonaSpacing.md)
        .animation(.smooth(duration: 0.6), value: speedKmh)
        .animation(.easeInOut, value: status)
        .dockCard()
    }

    private var color: Color {
        if searching { return EonaColor.textSecondary }
        switch status {
        case .over: return EonaColor.speedOver
        case .caution: return EonaColor.warning
        case .safe: return EonaColor.speedSafe
        case nil: return EonaColor.textPrimary
        }
    }

    /// The sign is also the way to propose a new limit when the road's has changed.
    @ViewBuilder
    private var sign: some View {
        if let onLimitClick {
            Button(action: onLimitClick) { signFace }
                .buttonStyle(.plain)
                .accessibilityHint("Signaler une nouvelle limitation")
        } else {
            signFace
        }
    }

    @ViewBuilder
    private var signFace: some View {
        if let limitKmh {
            SpeedLimitSign(limitKmh: limitKmh, size: 50)
        } else {
            UnknownLimitSign(size: 50)
        }
    }
}

/// "E4": how long the red light the driver waits at still has to run (fed by a later release).
private struct RedLightCard: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: EonaSpacing.xs) {
                EonaIconView(icon: .asset(.trafficLight), size: 20)
                Text("--")
                    .font(.xrTitle)
                    .lineLimit(1)
            }
            Text("Feu rouge")
                .font(.xrCaption)
                .lineLimit(1)
        }
        .foregroundStyle(EonaColor.textTertiary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, EonaSpacing.sm)
        .dockCard()
    }
}

/// Pulls the dock open onto the options.
private struct OptionsCard: View {
    let open: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(open ? EonaSymbol.chevronDown : EonaSymbol.chevronUp)
                    .font(.system(size: 13, weight: .semibold))
                Image(EonaSymbol.settings)
                    .font(.system(size: 18, weight: .medium))
                Text("Options")
                    .font(.xrCaption)
                    .lineLimit(1)
            }
            .foregroundStyle(EonaColor.textSecondary)
            .frame(width: 72)
            .dockCard(fill: open ? EonaColor.accent.opacity(0.18) : nil)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Which alerts show, and the route options. The alerts card keeps its place: its rows scroll
/// inside it, softly faded at an edge where some are hidden. Folded, it stops at "Accident"; the
/// arrow under it unfolds the rest.
private struct DockOptions: View {
    let preferences: PreferencesStore

    @State private var unfolded = false
    @State private var edges = ScrollEdges(above: false, below: false)

    private static let rowHeight: CGFloat = 44
    /// "Radar fixe" and the categories up to "Accident".
    private static let foldedRows = 1 + (ReportType.alertOptions.firstIndex(of: .accident).map { $0 + 1 } ?? 6)
    private static let fade: CGFloat = 10

    /// Height of [rows] rows and the lines between them.
    private static func height(rows: Int) -> CGFloat {
        CGFloat(rows) * rowHeight + CGFloat(max(rows - 1, 0)) * OptionDivider.thickness
    }

    var body: some View {
        let alerts = preferences.alerts
        let settings = preferences.settings
        let rows = 1 + ReportType.alertOptions.count
        ScrollViewReader { reader in
            VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                OptionTitle(text: "Alertes")
                ScrollView {
                    VStack(spacing: 0) {
                        OptionToggle(title: "Radar fixe", icon: .asset(.radar), tint: EonaColor.radarFixed, isOn: alerts.radarFixed) {
                            preferences.updateAlerts { $0.radarFixed.toggle() }
                        }
                        .id(0)
                        ForEach(Array(ReportType.alertOptions.enumerated()), id: \.element) { index, type in
                            OptionDivider()
                            OptionToggle(title: type.label, icon: type.optionIcon, tint: type.alertType.color, isOn: alerts.shows(type)) {
                                preferences.updateAlerts { $0.toggle(type) }
                            }
                            .id(index + 1)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
                    ScrollEdges(
                        above: geometry.contentOffset.y > 1,
                        below: geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1
                    )
                } action: { _, now in
                    edges = now
                }
                .mask { fadeMask }
                .frame(maxHeight: Self.height(rows: unfolded ? rows : Self.foldedRows))
                .background(EonaColor.surface.opacity(0.45), in: .rect(cornerRadius: EonaRadius.lg))
                .clipShape(.rect(cornerRadius: EonaRadius.lg))
                // First served: the card takes the room it needs, the route options stay under it.
                .layoutPriority(1)

                FoldArrow(unfolded: unfolded) {
                    withAnimation(.snappy) {
                        unfolded.toggle()
                    }
                    // Unfolded, the rest comes into view; folded, back to the top.
                    withAnimation(.snappy) {
                        reader.scrollTo(unfolded ? rows - 1 : 0, anchor: unfolded ? .bottom : .top)
                    }
                }

                OptionGroup(title: "Itinéraire") {
                    OptionToggle(title: "Éviter les péages", icon: .asset(.toll), tint: EonaColor.controlZone, isOn: settings.avoidTolls) {
                        preferences.updateSettings { $0.avoidTolls.toggle() }
                    }
                    OptionDivider()
                    OptionToggle(title: "Éviter les autoroutes", icon: .symbol(.navigation), tint: EonaColor.accent, isOn: settings.avoidHighways) {
                        preferences.updateSettings { $0.avoidHighways.toggle() }
                    }
                    OptionDivider()
                    OptionToggle(title: "Éviter les bouchons", icon: .asset(.reportTrafficJam), tint: EonaColor.warning, isOn: settings.avoidTraffic) {
                        preferences.updateSettings { $0.avoidTraffic.toggle() }
                    }
                }
                .padding(.top, EonaSpacing.sm)

                Spacer(minLength: 0)
            }
        }
    }

    /// Opaque in the middle, fading out at an edge only while rows hide beyond it.
    private var fadeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(edges.above ? 0 : 1), .black], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.fade)
            Rectangle()
            LinearGradient(colors: [.black, .black.opacity(edges.below ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.fade)
        }
    }
}

/// Whether rows hide above or below the visible part of a list.
nonisolated private struct ScrollEdges: Equatable, Sendable {
    let above: Bool
    let below: Bool
}

/// The small arrow under the alerts card: unfold the rest, or fold back.
private struct FoldArrow: View {
    let unfolded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(unfolded ? EonaSymbol.chevronUp : EonaSymbol.chevronDown)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(EonaColor.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unfolded ? "Replier les alertes" : "Afficher toutes les alertes")
    }
}

private struct OptionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.xrCaption)
            .foregroundStyle(EonaColor.textTertiary)
            .padding(.leading, EonaSpacing.xs)
    }
}

private struct OptionGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            OptionTitle(text: title)
            VStack(spacing: 0) {
                content
            }
            .background(EonaColor.surface.opacity(0.45), in: .rect(cornerRadius: EonaRadius.lg))
        }
    }
}

private struct OptionToggle: View {
    let title: String
    let icon: EonaIconImage
    let tint: Color
    let isOn: Bool
    let onToggle: @MainActor () -> Void

    var body: some View {
        EonaListRow(title: title, icon: icon, tint: tint) {
            Toggle(title, isOn: Binding(get: { isOn }, set: { _ in onToggle() }))
                .labelsHidden()
                .tint(EonaColor.accent)
        }
        .padding(.horizontal, EonaSpacing.md)
        // A fixed height, so the folded card ends exactly under a row.
        .frame(height: 44)
        .contentShape(.rect)
        .onTapGesture { onToggle() }
    }
}

private struct OptionDivider: View {
    static let thickness: CGFloat = 0.5

    var body: some View {
        Rectangle()
            .fill(EonaColor.separator)
            .frame(height: Self.thickness)
            .padding(.leading, 58)
    }
}

private extension View {
    /// The pale blocks of the dock: a lighter inner card on the glass.
    func dockCard(fill: Color? = nil) -> some View {
        frame(height: 82)
            .background(fill ?? EonaColor.surface.opacity(0.5), in: .rect(cornerRadius: EonaRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: EonaRadius.lg).strokeBorder(EonaColor.border, lineWidth: 1)
            }
    }
}
