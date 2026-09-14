import SwiftUI
import XRadarCore

/// "Nouvelle limitation", opened from the dock's limit sign. It is sign maintenance, not a road
/// event: the limit only changes for everyone once other drivers agree. The pick asks for a
/// confirmation that sends itself after a few seconds, like a report's direction.
struct SpeedLimitSheet: View {
    let currentKmh: Int?
    let onReport: (Int) -> Void

    @State private var picked: Int?

    var body: some View {
        DriveSheet {
            if let picked {
                LimitConfirm(currentKmh: currentKmh, newKmh: picked, onBack: { self.picked = nil }, onSend: onReport)
            } else {
                LimitPicker(currentKmh: currentKmh) { picked = $0 }
            }
        }
    }
}

/// What the HUD shows now, then every limit the map knows, three per row.
private struct LimitPicker: View {
    let currentKmh: Int?
    let onPick: (Int) -> Void

    private static let perRow = 3

    var body: some View {
        let rows = stride(from: 0, to: SpeedLimits.values.count, by: Self.perRow).map {
            Array(SpeedLimits.values[$0..<min($0 + Self.perRow, SpeedLimits.values.count)])
        }
        VStack(alignment: .leading, spacing: XRadarSpacing.lg) {
            Text("Nouvelle limitation")
                .font(.xrTitle)
                .foregroundStyle(XRadarColor.textPrimary)
            HStack(spacing: XRadarSpacing.md) {
                CurrentSign(kmh: currentKmh, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentKmh.map { "Limitation affichée : \($0) km/h" } ?? "Aucune limitation connue ici")
                        .font(.xrSubhead)
                        .foregroundStyle(XRadarColor.textPrimary)
                    Text("Choisis celle du panneau que tu vois.")
                        .font(.xrFootnote)
                        .foregroundStyle(XRadarColor.textSecondary)
                }
            }
            VStack(spacing: XRadarSpacing.md) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: XRadarSpacing.md) {
                        ForEach(0..<Self.perRow, id: \.self) { column in
                            if column < rows[index].count {
                                let kmh = rows[index][column]
                                LimitTile(kmh: kmh, isCurrent: kmh == currentKmh) { onPick(kmh) }
                            } else {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            Text("La limitation ne change pas tout de suite : elle est mise à jour quand d'autres conducteurs signalent la même.")
                .font(.xrFootnote)
                .foregroundStyle(XRadarColor.textTertiary)
        }
    }
}

/// "50 → 70": what changes, sent by itself when the countdown runs out.
private struct LimitConfirm: View {
    let currentKmh: Int?
    let newKmh: Int
    let onBack: () -> Void
    let onSend: (Int) -> Void

    @State private var auto = true
    @State private var sent = false

    var body: some View {
        let message = newKmh == currentKmh
            ? "Confirmer que la limitation affichée est la bonne."
            : "Signaler une limitation à \(newKmh) km/h ici, dans ton sens."
        VStack(alignment: .leading, spacing: XRadarSpacing.lg) {
            SheetBackTitle(title: "Nouvelle limitation") {
                auto = false
                onBack()
            }
            HStack(spacing: XRadarSpacing.lg) {
                CurrentSign(kmh: currentKmh, size: 64)
                Image(XRadarSymbol.chevronRight)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(XRadarColor.textTertiary)
                SpeedLimitSign(limitKmh: newKmh, size: 76)
            }
            .frame(maxWidth: .infinity)
            Text(message)
                .font(.xrSubhead)
                .foregroundStyle(XRadarColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            HStack(spacing: XRadarSpacing.md) {
                XRadarButton(title: "Envoyer", fillWidth: true) { send() }
                XRadarButton(title: "Changer", variant: .secondary, fillWidth: true) {
                    auto = false
                    onBack()
                }
            }
            if auto {
                AutoSendBar()
            }
        }
        .task(id: auto) {
            guard auto else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, auto else { return }
            send()
        }
    }

    private func send() {
        guard !sent else { return }
        sent = true
        onSend(newKmh)
    }
}

/// One limit to pick, drawn as the real sign.
private struct LimitTile: View {
    let kmh: Int
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: XRadarSpacing.sm) {
                SpeedLimitSign(limitKmh: kmh, size: 60)
                Text(isCurrent ? "Actuelle" : String("\(kmh) km/h"))
                    .font(.xrCaption)
                    .foregroundStyle(isCurrent ? XRadarColor.accent : XRadarColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, XRadarSpacing.sm)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// The limit shown now, or the empty sign when none is known.
private struct CurrentSign: View {
    let kmh: Int?
    let size: CGFloat

    var body: some View {
        if let kmh {
            SpeedLimitSign(limitKmh: kmh, size: size)
        } else {
            UnknownLimitSign(size: size)
        }
    }
}
