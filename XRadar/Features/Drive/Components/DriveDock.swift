import SwiftUI
import XRadarCore
import XRadarData

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
                        .padding(.bottom, XRadarSpacing.sm)
                }
                HStack(spacing: XRadarSpacing.sm) {
                    // Speed and red light share the width 1.45 to 1, as on Android.
                    GeometryReader { proxy in
                        let width = proxy.size.width - XRadarSpacing.sm
                        HStack(spacing: XRadarSpacing.sm) {
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
            ScrollView {
                DockOptions(preferences: preferences)
                    .padding(.top, XRadarSpacing.md)
                    .padding(.bottom, XRadarSpacing.sm)
            }
            .scrollIndicators(.hidden)
            .opacity(Double(progress))
            .allowsHitTesting(progress > 0.02)
            .accessibilityHidden(progress <= 0.02)
        }
        .padding(.horizontal, XRadarSpacing.md)
        .padding(.bottom, XRadarSpacing.md)
        .frame(maxWidth: .infinity)
        .frame(height: collapsed + travel * progress, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: XRadarRadius.xxl))
        .onChange(of: progress > Self.openThreshold) { _, open in
            onOpenChange(open)
        }
    }

    private var handle: some View {
        Capsule()
            .fill(XRadarColor.borderStrong)
            .frame(width: 44, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.vertical, XRadarSpacing.sm)
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
        HStack(spacing: XRadarSpacing.sm) {
            cluster(trip.remainingLabel, "Restantes", XRadarColor.accent)
            cluster(trip.distanceLabel, "Distance", XRadarColor.textPrimary)
            cluster(trip.arrivalLabel, "Arrivée", XRadarColor.textPrimary)
        }
        .padding(.horizontal, XRadarSpacing.xs)
    }

    private func cluster(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.xrBodyStrong.monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.xrCaption)
                .foregroundStyle(XRadarColor.textTertiary)
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
        HStack(spacing: XRadarSpacing.sm) {
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
                    .foregroundStyle(XRadarColor.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            sign
        }
        .padding(.horizontal, XRadarSpacing.md)
        .animation(.smooth(duration: 0.6), value: speedKmh)
        .animation(.easeInOut, value: status)
        .dockCard()
    }

    private var color: Color {
        if searching { return XRadarColor.textSecondary }
        switch status {
        case .over: return XRadarColor.speedOver
        case .caution: return XRadarColor.warning
        case .safe: return XRadarColor.speedSafe
        case nil: return XRadarColor.textPrimary
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
            HStack(spacing: XRadarSpacing.xs) {
                XRadarIconView(icon: .asset(.trafficLight), size: 20)
                Text("--")
                    .font(.xrTitle)
                    .lineLimit(1)
            }
            Text("Feu rouge")
                .font(.xrCaption)
                .lineLimit(1)
        }
        .foregroundStyle(XRadarColor.textTertiary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, XRadarSpacing.sm)
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
                Image(open ? XRadarSymbol.chevronDown : XRadarSymbol.chevronUp)
                    .font(.system(size: 13, weight: .semibold))
                Image(XRadarSymbol.settings)
                    .font(.system(size: 18, weight: .medium))
                Text("Options")
                    .font(.xrCaption)
                    .lineLimit(1)
            }
            .foregroundStyle(XRadarColor.textSecondary)
            .frame(width: 72)
            .dockCard(fill: open ? XRadarColor.accent.opacity(0.18) : nil)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Everything the old options sheet held: which alerts show, and the route options.
private struct DockOptions: View {
    let preferences: PreferencesStore

    var body: some View {
        let alerts = preferences.alerts
        let settings = preferences.settings
        VStack(alignment: .leading, spacing: XRadarSpacing.lg) {
            OptionGroup(title: "Alertes") {
                OptionToggle(title: "Radar fixe", icon: .asset(.radar), tint: XRadarColor.radarFixed, isOn: alerts.radarFixed) {
                    preferences.updateAlerts { $0.radarFixed.toggle() }
                }
                OptionDivider()
                OptionToggle(title: "Radar mobile", icon: .asset(.radar), tint: XRadarColor.radarMobile, isOn: alerts.radarMobile) {
                    preferences.updateAlerts { $0.radarMobile.toggle() }
                }
                OptionDivider()
                OptionToggle(title: "Caméra (voie publique)", icon: .asset(.camera), tint: XRadarColor.radarFixed, isOn: alerts.cameras) {
                    preferences.updateAlerts { $0.cameras.toggle() }
                }
                OptionDivider()
                OptionToggle(title: "Zone de contrôle", icon: .asset(.shield), tint: XRadarColor.controlZone, isOn: alerts.controlZones) {
                    preferences.updateAlerts { $0.controlZones.toggle() }
                }
                OptionDivider()
                OptionToggle(title: "Danger & travaux", icon: .symbol(.warning), tint: XRadarColor.hazard, isOn: alerts.hazards) {
                    preferences.updateAlerts { $0.hazards.toggle() }
                }
            }
            OptionGroup(title: "Itinéraire") {
                OptionToggle(title: "Éviter les péages", icon: .asset(.toll), tint: XRadarColor.controlZone, isOn: settings.avoidTolls) {
                    preferences.updateSettings { $0.avoidTolls.toggle() }
                }
                OptionDivider()
                OptionToggle(title: "Éviter les autoroutes", icon: .symbol(.navigation), tint: XRadarColor.accent, isOn: settings.avoidHighways) {
                    preferences.updateSettings { $0.avoidHighways.toggle() }
                }
            }
        }
    }
}

private struct OptionGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: XRadarSpacing.sm) {
            Text(title.uppercased())
                .font(.xrCaption)
                .foregroundStyle(XRadarColor.textTertiary)
                .padding(.leading, XRadarSpacing.xs)
            VStack(spacing: 0) {
                content
            }
            .background(XRadarColor.surface.opacity(0.45), in: .rect(cornerRadius: XRadarRadius.lg))
        }
    }
}

private struct OptionToggle: View {
    let title: String
    let icon: XRadarIconImage
    let tint: Color
    let isOn: Bool
    let onToggle: @MainActor () -> Void

    var body: some View {
        XRadarListRow(title: title, icon: icon, tint: tint) {
            Toggle(title, isOn: Binding(get: { isOn }, set: { _ in onToggle() }))
                .labelsHidden()
                .tint(XRadarColor.accent)
        }
        .padding(.horizontal, XRadarSpacing.md)
        .padding(.vertical, XRadarSpacing.sm)
        .contentShape(.rect)
        .onTapGesture { onToggle() }
    }
}

private struct OptionDivider: View {
    var body: some View {
        Divider().padding(.leading, 58)
    }
}

private extension View {
    /// The pale blocks of the dock: a lighter inner card on the glass.
    func dockCard(fill: Color? = nil) -> some View {
        frame(height: 82)
            .background(fill ?? XRadarColor.surface.opacity(0.5), in: .rect(cornerRadius: XRadarRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: XRadarRadius.lg).strokeBorder(XRadarColor.border, lineWidth: 1)
            }
    }
}
