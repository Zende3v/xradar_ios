import SwiftUI
import EonaCore

/// Every alert live right now, in one compact card, as on Android. The alert in focus (the
/// nearest, unless the driver tapped another) fills one line: what, where, how far; the others
/// wait beneath as chips, a tap away, and past three the rest sit behind "+N", in a sheet that
/// lists them all. Swiping the card sideways throws the alert in focus away.
struct AlertStack: View {
    let alerts: [RoadAlert]
    let onDismiss: (String) -> Void
    /// Whether the driver can still say if this alert is there ("toujours là / plus là").
    let canVote: (RoadAlert) -> Bool
    let onVote: (RoadAlert, Bool) -> Void

    @State private var lastOrder: [String] = []
    @State private var pinned: String?
    @State private var listOpen = false

    private static let maxChips = 3
    /// Two alerts closer than this keep their order: GPS noise must not shuffle the chips.
    private static let swapMarginMeters = 30
    /// How long an alert the driver picked stays in focus before the nearest takes over.
    private static let pinSeconds = 10.0

    var body: some View {
        let ordered = RoadAlert.stableOrder(previous: lastOrder, alerts: alerts, marginMeters: Self.swapMarginMeters)
        if let nearest = ordered.first {
            let focus = ordered.first { $0.key == pinned } ?? nearest
            let isPinned = focus.key != nearest.key
            SwipeAway(onDismiss: { onDismiss(focus.key) }) {
                card(focus: focus, isPinned: isPinned, others: ordered.filter { $0.key != focus.key })
            }
            .id(focus.key)
            .onChange(of: ordered.map(\.key), initial: true) { _, keys in
                lastOrder = keys
            }
            .onChange(of: alerts.map(\.key)) { _, keys in
                if let pinned, !keys.contains(pinned) { self.pinned = nil }
            }
            .task(id: pinned) {
                guard pinned != nil else { return }
                try? await Task.sleep(for: .seconds(Self.pinSeconds))
                if !Task.isCancelled { pinned = nil }
            }
            .sheet(isPresented: $listOpen) {
                AlertListSheet(alerts: ordered, focusKey: focus.key) { alert in
                    pinned = alert.key
                    listOpen = false
                }
            }
        }
    }

    private func card(focus: RoadAlert, isPinned: Bool, others: [RoadAlert]) -> some View {
        let accent = focus.type.color
        return VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            FocusLine(alert: focus)
            // Crowd reports carry a reliability; a fixed radar does not need one.
            if focus.lastReportedLabel != nil {
                ProgressBar(value: focus.confidence, color: accent, height: 3)
            }
            if canVote(focus) {
                VoteRow { confirm in onVote(focus, confirm) }
            }
            if !others.isEmpty {
                HStack(spacing: EonaSpacing.sm) {
                    ForEach(others.prefix(Self.maxChips), id: \.key) { alert in
                        AlertChip(alert: alert) { pinned = alert.key }
                    }
                    if others.count > Self.maxChips {
                        MoreChip(count: others.count - Self.maxChips) { listOpen = true }
                    }
                }
            }
        }
        .padding(.horizontal, EonaSpacing.md)
        .padding(.vertical, EonaSpacing.sm + EonaSpacing.hair)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: EonaRadius.xl))
        .overlay {
            // A picked alert is outlined in its color; a tap on the card goes back to the nearest.
            if isPinned {
                RoundedRectangle(cornerRadius: EonaRadius.xl).strokeBorder(accent, lineWidth: 1.5)
            }
        }
        .contentShape(.rect(cornerRadius: EonaRadius.xl))
        .onTapGesture {
            if isPinned { pinned = nil }
        }
    }
}

private extension RoadAlert {
    /// "Sens opposé · 2 signalements · il y a 4 min".
    var detail: String {
        [subtitle, lastReportedLabel ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// The alert in focus on one line: icon, what and where, distance and time to it.
private struct FocusLine: View {
    let alert: RoadAlert

    var body: some View {
        HStack(spacing: EonaSpacing.md) {
            AlertIconTile(type: alert.type, size: 40, iconSize: 22, radius: EonaRadius.md)
            VStack(alignment: .leading, spacing: 0) {
                Text(alert.title)
                    .font(.xrHeadline)
                    .foregroundStyle(EonaColor.textPrimary)
                    .lineLimit(1)
                if !alert.detail.isEmpty {
                    Text(alert.detail)
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                Text(RoadAlert.distanceLabel(alert.distanceMeters))
                    .font(.xrTitle.weight(.bold).monospacedDigit())
                    .foregroundStyle(alert.type.color)
                    .lineLimit(1)
                Text("dans \(alert.etaSeconds) s")
                    .font(.xrCaption)
                    .foregroundStyle(EonaColor.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AlertIconTile: View {
    let type: AlertType
    let size: CGFloat
    let iconSize: CGFloat
    let radius: CGFloat

    var body: some View {
        EonaIconView(icon: type.icon, size: iconSize)
            .foregroundStyle(type.color)
            .frame(width: size, height: size)
            .background(type.color.opacity(0.14), in: .rect(cornerRadius: radius))
    }
}

private struct ProgressBar: View {
    let value: Double
    let color: Color
    let height: CGFloat

    var body: some View {
        Capsule()
            .fill(EonaColor.surfaceHigh)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * CGFloat(min(max(value, 0), 1)))
                }
            }
    }
}

/// "Toujours là" / "Plus là" for a crowd report close ahead: the driver's one voice on it.
private struct VoteRow: View {
    let onVote: (Bool) -> Void

    var body: some View {
        HStack(spacing: EonaSpacing.sm) {
            button("Toujours là", .check, EonaColor.accent) { onVote(true) }
            button("Plus là", .close, EonaColor.textSecondary) { onVote(false) }
        }
    }

    private func button(_ label: String, _ symbol: EonaSymbol, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: EonaSpacing.xs) {
                Image(symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.xrFootnote.weight(.semibold))
                    .foregroundStyle(EonaColor.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(tint.opacity(0.12), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// Another live alert, as a chip: its icon in its color and how far it is.
private struct AlertChip: View {
    let alert: RoadAlert
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: EonaSpacing.xs) {
                EonaIconView(icon: alert.type.icon, size: 16)
                    .foregroundStyle(alert.type.color)
                Text(RoadAlert.distanceLabel(alert.distanceMeters))
                    .font(.xrFootnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(EonaColor.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, EonaSpacing.sm)
            .padding(.vertical, EonaSpacing.xs)
            .background(alert.type.color.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(alert.title)
    }
}

/// "+2": the alerts that do not fit as chips, one tap from the full list.
private struct MoreChip: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("+\(count)")
                .font(.xrFootnote.weight(.semibold))
                .foregroundStyle(EonaColor.textSecondary)
                .padding(.horizontal, EonaSpacing.sm)
                .padding(.vertical, EonaSpacing.xs)
                .background(EonaColor.surfaceHigh, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// All live alerts, nearest first; picking one brings it into focus on the HUD.
private struct AlertListSheet: View {
    let alerts: [RoadAlert]
    let focusKey: String
    let onPick: (RoadAlert) -> Void

    var body: some View {
        let title = alerts.count == 1 ? "1 alerte" : "\(alerts.count) alertes"
        ScrollView {
            VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                Text(title)
                    .font(.xrTitle)
                    .foregroundStyle(EonaColor.textPrimary)
                ForEach(alerts, id: \.key) { alert in
                    row(alert)
                }
            }
            .padding(.horizontal, EonaSpacing.lg)
            .padding(.top, EonaSpacing.xxl)
            .padding(.bottom, EonaSpacing.lg)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ alert: RoadAlert) -> some View {
        Button {
            onPick(alert)
        } label: {
            HStack(spacing: EonaSpacing.sm) {
                AlertIconTile(type: alert.type, size: 30, iconSize: 18, radius: EonaRadius.sm)
                VStack(alignment: .leading, spacing: 0) {
                    Text(alert.title)
                        .font(.xrCallout)
                        .foregroundStyle(EonaColor.textPrimary)
                        .lineLimit(1)
                    if !alert.detail.isEmpty {
                        Text(alert.detail)
                            .font(.xrCaption)
                            .foregroundStyle(EonaColor.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(RoadAlert.distanceLabel(alert.distanceMeters))
                    .font(.xrCallout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(alert.type.color)
            }
            .padding(.vertical, EonaSpacing.xs)
            .padding(.horizontal, EonaSpacing.sm)
            .background(alert.key == focusKey ? alert.type.color.opacity(0.10) : Color.clear, in: .rect(cornerRadius: EonaRadius.md))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Drag sideways to throw an alert away: past 30 % of the width, or on a flick the same way, it
/// leaves the screen and [onDismiss] runs; otherwise it springs back. A new alert (a new view
/// identity) starts back in place with a short fade in.
private struct SwipeAway<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    @State private var leaving = false
    @State private var width: CGFloat = 1
    @State private var appeared = false

    var body: some View {
        let gone = min(abs(offset) / max(width, 1), 1)
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .scaleEffect(appeared ? 1 : 0.96)
            .opacity((appeared ? 1 : 0) * Double(1 - gone * 0.85))
            .rotationEffect(.degrees(Double(offset / max(width, 1)) * 4))
            .offset(x: offset)
            .gesture(drag, including: leaving ? .none : .all)
            .onAppear {
                withAnimation(.easeOut(duration: 0.22)) { appeared = true }
            }
            .task(id: leaving) {
                // Safety net: a card that left but whose alert never went away comes back.
                guard leaving else { return }
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                offset = 0
                leaving = false
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                offset = value.translation.width
            }
            .onEnded { value in
                let velocity = value.velocity.width
                let flung = abs(velocity) > 330 && (abs(offset) < 1 || (velocity < 0) == (offset < 0))
                guard flung || abs(offset) > width * 0.3 else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { offset = 0 }
                    return
                }
                leaving = true
                let direction: CGFloat = (flung ? velocity : offset) < 0 ? -1 : 1
                withAnimation(.easeOut(duration: 0.18)) {
                    offset = direction * width * 1.15
                } completion: {
                    onDismiss()
                }
            }
    }
}
