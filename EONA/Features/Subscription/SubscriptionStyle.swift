import SwiftUI

/// Pastels EONA+ : référence Telegram Premium choisie par Arthur. Fond OLED conservé.
enum EonaPlusStyle {
    static let canvas = Color(red: 10 / 255.0, green: 10 / 255.0, blue: 12 / 255.0)
    static let surface = Color(red: 28 / 255.0, green: 28 / 255.0, blue: 30 / 255.0)
    static let primary = Color(red: 245 / 255.0, green: 245 / 255.0, blue: 247 / 255.0)
    static let secondary = Color(red: 164 / 255.0, green: 164 / 255.0, blue: 172 / 255.0)
    static let muted = Color(red: 133 / 255.0, green: 133 / 255.0, blue: 141 / 255.0)
    static let mineral = Color(red: 176 / 255.0, green: 181 / 255.0, blue: 187 / 255.0)
    static let sky = Color(red: 159 / 255.0, green: 202 / 255.0, blue: 241 / 255.0)
    static let lavender = Color(red: 189 / 255.0, green: 178 / 255.0, blue: 238 / 255.0)
    static let pink = Color(red: 230 / 255.0, green: 174 / 255.0, blue: 211 / 255.0)
    static let peach = Color(red: 241 / 255.0, green: 192 / 255.0, blue: 167 / 255.0)
    static let mint = Color(red: 172 / 255.0, green: 217 / 255.0, blue: 201 / 255.0)
    static let spectrum = [sky, lavender, pink, peach, mint]
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
            .font(.caption.weight(.medium))
            .tracking(1.2)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct EonaPlusDivider: View {
    var body: some View {
        Rectangle().fill(EonaPlusStyle.line).frame(height: 0.5)
    }
}

/// Une surface commune aux lignes, sans cartes répétées pour chaque fonction.
struct EonaPlusGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(EonaPlusStyle.surface, in: .rect(cornerRadius: 26))
            .clipShape(.rect(cornerRadius: 26))
            .overlay {
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(EonaPlusStyle.line, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

/// Action pastel fixe, indépendante de couleur choisie dans réglages.
struct EonaPlusAction: View {
    let title: String
    var symbol = "arrow.right"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: EonaSpacing.sm) {
                Text(title).font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: symbol).font(.footnote.weight(.semibold))
            }
            .foregroundStyle(EonaPlusStyle.canvas)
            .padding(.horizontal, EonaSpacing.xl)
            .padding(.vertical, EonaSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                Capsule().fill(LinearGradient(colors: [EonaPlusStyle.sky, EonaPlusStyle.lavender, EonaPlusStyle.pink], startPoint: .leading, endPoint: .trailing))
            }
            .overlay { Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}