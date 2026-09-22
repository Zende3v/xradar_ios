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
/// of the AirPods: the one in use is filled, a tap picks another and the bar closes again.
///
/// Every choice is always in the view hierarchy — the closed ones simply have no width. Nothing
/// is inserted or removed while the bar moves, so a finger landing mid-animation hits the button
/// it aimed at instead of nothing.
struct AudioOptionBar<Value: Hashable>: View {
    let options: [AudioOption<Value>]
    let selected: Value
    let label: String
    @Binding var open: Bool
    let onPick: (Value) -> Void

    var size: CGFloat = 48

    var body: some View {
        HStack(spacing: open ? EonaSpacing.xs : 0) {
            ForEach(options) { option in
                let shown = open || option.value == selected
                Button {
                    if open {
                        onPick(option.value)
                        close()
                    } else {
                        withAnimation(AudioBarMotion.spring) { open = true }
                    }
                } label: {
                    EonaIconView(icon: .symbol(option.icon), size: size * 0.44)
                        .foregroundStyle(tint(for: option))
                        .frame(width: shown ? size : 0, height: size)
                        .background {
                            if open, option.value == selected {
                                Circle().fill(EonaColor.accent)
                            }
                        }
                        .opacity(shown ? 1 : 0)
                        .clipShape(.circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .disabled(!shown)
                .accessibilityLabel(option.label)
                .accessibilityHidden(!shown)
                .accessibilityAddTraits(option.value == selected ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, open ? EonaSpacing.xs : 0)
        .frame(height: open ? size + EonaSpacing.xs * 2 : size)
        // A capsule as wide as it is tall is a circle: one shape, closed or open.
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .animation(AudioBarMotion.spring, value: open)
        .animation(AudioBarMotion.spring, value: selected)
    }

    private func tint(for option: AudioOption<Value>) -> Color {
        open && option.value == selected ? EonaColor.onAccent : EonaColor.textPrimary
    }

    private func close() {
        withAnimation(AudioBarMotion.spring) { open = false }
    }
}

/// Opens and closes at a pace the eye follows: half a second, settling without a bounce.
enum AudioBarMotion {
    static let spring: Animation = .spring(response: 0.55, dampingFraction: 0.9)
}
