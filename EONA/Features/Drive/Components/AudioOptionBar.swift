import SwiftUI

/// One of the sound choices shown when the bar is open.
struct AudioOption<Value: Hashable>: Identifiable {
    let value: Value
    let icon: EonaSymbol
    let label: String

    var id: Value { value }
}

/// The two audio buttons over the dock. Closed, each is a plain round button showing what is on.
/// Tapped, it opens to the right and lays its choices side by side, like the noise-control picker
/// of the AirPods: the one in use is filled, a tap picks another and the bar closes again. The
/// glass is the app's, so it sits on the map like everything else.
struct AudioOptionBar<Value: Hashable>: View {
    let options: [AudioOption<Value>]
    let selected: Value
    let label: String
    @Binding var open: Bool
    let onPick: (Value) -> Void

    var size: CGFloat = 48

    var body: some View {
        GlassEffectContainer(spacing: EonaSpacing.xs) {
            if open {
                HStack(spacing: EonaSpacing.xs) {
                    ForEach(options) { option in
                        Button {
                            onPick(option.value)
                            close()
                        } label: {
                            EonaIconView(icon: .symbol(option.icon), size: size * 0.44)
                                .foregroundStyle(option.value == selected ? EonaColor.onAccent : EonaColor.textPrimary)
                                .frame(width: size, height: size)
                                .background {
                                    if option.value == selected {
                                        Circle().fill(EonaColor.accent)
                                    }
                                }
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.label)
                        .accessibilityAddTraits(option.value == selected ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, EonaSpacing.xs)
                .frame(height: size + EonaSpacing.xs * 2)
                .glassEffect(.regular.interactive(), in: .capsule)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.4, anchor: .leading).combined(with: .opacity),
                    removal: .scale(scale: 0.4, anchor: .leading).combined(with: .opacity)
                ))
            } else {
                EonaIconButton(icon: .symbol(current), label: label, size: size) {
                    withAnimation(AudioBarMotion.spring) { open = true }
                }
            }
        }
        .animation(AudioBarMotion.spring, value: open)
    }

    /// The icon of the choice in use: what the closed button shows.
    private var current: EonaSymbol {
        options.first { $0.value == selected }?.icon ?? options[0].icon
    }

    private func close() {
        withAnimation(AudioBarMotion.spring) { open = false }
    }

}

/// Opens and closes with a short spring, never a jump.
enum AudioBarMotion {
    static let spring: Animation = .spring(response: 0.32, dampingFraction: 0.82)
}
