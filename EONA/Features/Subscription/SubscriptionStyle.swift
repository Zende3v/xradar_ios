import SwiftUI

/// Palette locale EONA+. OLED constant ; aucune dépendance à couleur choisie dans réglages.
enum EonaPlusStyle {
    static let canvas = Color(red: 10 / 255.0, green: 10 / 255.0, blue: 12 / 255.0)
    static let primary = Color(red: 242 / 255.0, green: 241 / 255.0, blue: 237 / 255.0)
    static let secondary = Color(red: 165 / 255.0, green: 169 / 255.0, blue: 176 / 255.0)
    static let muted = Color(red: 115 / 255.0, green: 119 / 255.0, blue: 126 / 255.0)
    static let mineral = Color(red: 176 / 255.0, green: 181 / 255.0, blue: 187 / 255.0)
    static let amber = Color(red: 226 / 255.0, green: 181 / 255.0, blue: 110 / 255.0)
    static let line = Color.white.opacity(0.08)
}

struct EonaPlusLabel: View {
    let text: String
    var color: Color

    init(_ text: String, color: Color = EonaPlusStyle.secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption2, design: .monospaced).weight(.medium))
            .tracking(1.8)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct EonaPlusDivider: View {
    var body: some View {
        Rectangle().fill(EonaPlusStyle.line).frame(height: 0.5)
    }
}

/// Action en verre teinté ambre. Libellé à gauche, aucun halo ajouté.
struct EonaPlusAction: View {
    let title: String
    var symbol = "arrow.right"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: EonaSpacing.md) {
                Text(title).font(.xrLabel)
                Spacer(minLength: EonaSpacing.md)
                Image(systemName: symbol).font(.footnote.weight(.medium))
            }
            .foregroundStyle(EonaPlusStyle.amber)
            .padding(.horizontal, EonaSpacing.xl)
            .padding(.vertical, EonaSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(EonaPlusStyle.amber.opacity(0.12)).interactive(), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(EonaPlusStyle.line, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }
}
