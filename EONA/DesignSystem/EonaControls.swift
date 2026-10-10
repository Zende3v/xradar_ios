import SwiftUI

enum EonaButtonVariant {
    case primary
    case secondary
    case ghost
    case destructive
}

/// The one text button, in Liquid Glass: prominent and tinted for the main action, clear glass
/// for a secondary one, bare text for a ghost. Loading swaps the label for a spinner.
struct EonaButton: View {
    let title: String
    var systemImage: EonaSymbol? = nil
    var variant: EonaButtonVariant = .primary
    var loading = false
    var fillWidth = false
    let action: () -> Void

    var body: some View {
        styled(
            Button(action: action) {
                HStack(spacing: EonaSpacing.sm) {
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
                .foregroundStyle(labelStyle)
                .frame(maxWidth: fillWidth ? .infinity : nil)
                .padding(.horizontal, usesPalette ? EonaSpacing.xl : 0)
                .padding(.vertical, usesPalette ? EonaSpacing.md : 0)
                .contentShape(Capsule())
            }
            .controlSize(.large)
            .disabled(loading)
        )
    }

    private var labelColor: Color {
        switch variant {
        case .primary: EonaColor.onAccent
        case .secondary: EonaColor.textPrimary
        case .ghost: EonaColor.accent
        case .destructive: .white
        }
    }

    private var labelStyle: AnyShapeStyle {
        if case .ghost = variant, EonaColor.accentSelection.isMulticolour {
            return AnyShapeStyle(EonaColor.accentControlGradient)
        }
        return AnyShapeStyle(labelColor)
    }

    private var usesPalette: Bool {
        if case .primary = variant { return EonaColor.accentSelection.isMulticolour }
        return false
    }

    @ViewBuilder
    private func styled(_ button: some View) -> some View {
        switch variant {
        case .primary:
            if EonaColor.accentSelection.isMulticolour {
                button
                    .buttonStyle(.plain)
                    .background(EonaColor.accentFillGradient, in: .capsule)
                    .glassEffect(.clear.interactive(), in: .capsule)
                    .opacity(loading ? 0.55 : 1)
            } else {
                button.buttonStyle(.glassProminent).tint(EonaColor.accent)
            }
        case .secondary:
            button.buttonStyle(.glass)
        case .ghost:
            button.buttonStyle(.borderless)
        case .destructive:
            button.buttonStyle(.glassProminent).tint(EonaColor.danger)
        }
    }
}

/// Round icon button: on glass for the buttons floating over the map, bare in bars.
struct EonaIconButton: View {
    let icon: EonaIconImage
    let label: String
    var size: CGFloat = 44
    var tint: Color = EonaColor.textPrimary
    var glass = true
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            EonaIconView(icon: icon, size: size * 0.46)
                .foregroundStyle(iconStyle)
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

    private var iconStyle: AnyShapeStyle {
        if case .symbol(.recenter) = icon, EonaColor.accentSelection.isMulticolour {
            return AnyShapeStyle(EonaColor.accentControlGradient)
        }
        return AnyShapeStyle(tint)
    }
}

/// Capsule EONA : sélection et palette partagées ; chevron facultatif pour menus.
struct EonaChip: View {
    let label: String
    var dot: Color? = nil
    var trailing: String? = nil
    var selected = false
    var disclosure = false
    var action: (() -> Void)? = nil

    var body: some View {
        let content = HStack(spacing: EonaSpacing.sm) {
            if let dot {
                Circle()
                    .fill(dot)
                    .frame(width: 8, height: 8)
            }
            Text(label)
                .font(.xrSubhead)
                .foregroundStyle(paletteSelected ? AnyShapeStyle(EonaColor.onAccent) : selected ? AnyShapeStyle(EonaColor.accentGradient) : AnyShapeStyle(EonaColor.textPrimary))
            if let trailing {
                Text(trailing)
                    .font(.xrCaption)
                    .foregroundStyle(paletteSelected ? EonaColor.onAccent.opacity(0.65) : EonaColor.textTertiary)
            }
            if disclosure {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(paletteSelected ? EonaColor.onAccent.opacity(0.65) : EonaColor.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, EonaSpacing.md)
        .padding(.vertical, EonaSpacing.sm)
        .background {
            if paletteSelected { Capsule().fill(EonaColor.accentFillGradient) }
        }
        .glassEffect(paletteSelected ? Glass.clear.interactive() : selected ? Glass.regular.tint(EonaColor.accent.opacity(0.25)).interactive() : Glass.regular.interactive(), in: .capsule)

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var paletteSelected: Bool { selected && EonaColor.accentSelection.isMulticolour }
}

/// Small status label: tinted text on a faint fill of the same hue, or, with [glow], white text
/// glowing on the dark tile of the Menu's icons.
struct EonaBadge: View {
    let text: String
    var color: Color = EonaColor.accent
    var glow = false

    var body: some View {
        Text(text.uppercased())
            .font(.xrCaption)
            .foregroundStyle(glow ? EonaColor.glowIcon : color)
            .shadow(color: glow ? EonaColor.glowIcon.opacity(0.6) : .clear, radius: 3)
            .padding(.horizontal, EonaSpacing.sm)
            .padding(.vertical, EonaSpacing.xs)
            .background(glow ? EonaColor.glowTile : color.opacity(0.14), in: .capsule)
    }
}

/// Search input with a clear button, filled: it lies on the search's glass (no glass on glass).
struct EonaSearchField: View {
    @Binding var text: String
    var placeholder = "Rechercher une destination"
    var autoFocus = false
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: EonaSpacing.sm) {
            Image(EonaSymbol.search)
                .foregroundStyle(EonaColor.textTertiary)
            TextField(placeholder, text: $text)
                .font(.xrBody)
                .foregroundStyle(EonaColor.textPrimary)
                .tint(EonaColor.accent)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(EonaSymbol.close)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(EonaColor.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer")
            }
        }
        .padding(.horizontal, EonaSpacing.md)
        .frame(minHeight: 44)
        .background(EonaColor.surface.opacity(0.45), in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(EonaColor.separator, lineWidth: 0.5)
        }
        .onAppear {
            if autoFocus { focused = true }
        }
    }
}
