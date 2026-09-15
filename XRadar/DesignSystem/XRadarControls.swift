import SwiftUI

enum XRadarButtonVariant {
    case primary
    case secondary
    case ghost
    case destructive
}

/// The one text button, in Liquid Glass: prominent and tinted for the main action, clear glass
/// for a secondary one, bare text for a ghost. Loading swaps the label for a spinner.
struct XRadarButton: View {
    let title: String
    var systemImage: XRadarSymbol? = nil
    var variant: XRadarButtonVariant = .primary
    var loading = false
    var fillWidth = false
    let action: () -> Void

    var body: some View {
        styled(
            Button(action: action) {
                HStack(spacing: XRadarSpacing.sm) {
                    if loading {
                        ProgressView()
                            .tint(labelColor)
                    } else {
                        if let systemImage {
                            Image(systemImage)
                        }
                        Text(title)
                    }
                }
                .font(.xrLabel)
                .foregroundStyle(labelColor)
                .frame(maxWidth: fillWidth ? .infinity : nil)
            }
            .controlSize(.large)
            .disabled(loading)
        )
    }

    private var labelColor: Color {
        switch variant {
        case .primary: XRadarColor.onAccent
        case .secondary: XRadarColor.textPrimary
        case .ghost: XRadarColor.accent
        case .destructive: .white
        }
    }

    @ViewBuilder
    private func styled(_ button: some View) -> some View {
        switch variant {
        case .primary:
            button.buttonStyle(.glassProminent).tint(XRadarColor.accent)
        case .secondary:
            button.buttonStyle(.glass)
        case .ghost:
            button.buttonStyle(.borderless)
        case .destructive:
            button.buttonStyle(.glassProminent).tint(XRadarColor.danger)
        }
    }
}

/// Round icon button: on glass for the buttons floating over the map, bare in bars.
struct XRadarIconButton: View {
    let icon: XRadarIconImage
    let label: String
    var size: CGFloat = 44
    var tint: Color = XRadarColor.textPrimary
    var glass = true
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            XRadarIconView(icon: icon, size: size * 0.46)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)

        if glass {
            button.glassEffect(.regular.interactive(), in: .circle)
        } else {
            button
        }
    }
}

/// Pill chip: an optional status dot, a label, optional meta. Selected takes the accent.
struct XRadarChip: View {
    let label: String
    var dot: Color? = nil
    var trailing: String? = nil
    var selected = false
    var action: (() -> Void)? = nil

    var body: some View {
        let content = HStack(spacing: XRadarSpacing.sm) {
            if let dot {
                Circle()
                    .fill(dot)
                    .frame(width: 8, height: 8)
            }
            Text(label)
                .font(.xrSubhead)
                .foregroundStyle(selected ? XRadarColor.accent : XRadarColor.textPrimary)
            if let trailing {
                Text(trailing)
                    .font(.xrCaption)
                    .foregroundStyle(XRadarColor.textTertiary)
            }
        }
        .padding(.horizontal, XRadarSpacing.md)
        .padding(.vertical, XRadarSpacing.sm)
        .glassEffect(selected ? Glass.regular.tint(XRadarColor.accent.opacity(0.25)).interactive() : Glass.regular.interactive(), in: .capsule)

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

/// Small status label: tinted text on a faint fill of the same hue, or, with [glow], white text
/// glowing on the dark tile of the Menu's icons.
struct XRadarBadge: View {
    let text: String
    var color: Color = XRadarColor.accent
    var glow = false

    var body: some View {
        Text(text.uppercased())
            .font(.xrCaption)
            .foregroundStyle(glow ? XRadarColor.glowIcon : color)
            .shadow(color: glow ? XRadarColor.glowIcon.opacity(0.6) : .clear, radius: 3)
            .padding(.horizontal, XRadarSpacing.sm)
            .padding(.vertical, XRadarSpacing.xs)
            .background(glow ? XRadarColor.glowTile : color.opacity(0.14), in: .capsule)
    }
}

/// Search input on glass, with a clear button.
struct XRadarSearchField: View {
    @Binding var text: String
    var placeholder = "Rechercher une destination"
    var autoFocus = false
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: XRadarSpacing.sm) {
            Image(XRadarSymbol.search)
                .foregroundStyle(XRadarColor.textTertiary)
            TextField(placeholder, text: $text)
                .font(.xrBody)
                .foregroundStyle(XRadarColor.textPrimary)
                .tint(XRadarColor.accent)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(XRadarSymbol.close)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(XRadarColor.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer")
            }
        }
        .padding(.horizontal, XRadarSpacing.md)
        .frame(minHeight: 44)
        .glassEffect(.regular.interactive(), in: .capsule)
        .onAppear {
            if autoFocus { focused = true }
        }
    }
}
