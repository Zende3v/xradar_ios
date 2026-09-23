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
/// Only the width moves. The bar keeps its height open or closed, every choice stays in the
/// hierarchy (the hidden ones have no width), and the highlight fades rather than appears — so
/// opening and closing is one steady stretch, with nothing popping in or out on the way.
struct AudioOptionBar<Value: Hashable>: View {
    let options: [AudioOption<Value>]
    let selected: Value
    let label: String
    @Binding var open: Bool
    let onPick: (Value) -> Void

    var size: CGFloat = 48

    var body: some View {
        // Open, the choices sit inside the capsule's inset: the bar grows sideways only.
        let inset = open ? EonaSpacing.xs : 0
        let chip = size - inset * 2
        HStack(spacing: open ? EonaSpacing.xs : 0) {
            ForEach(options) { option in
                let shown = open || option.value == selected
                let current = open && option.value == selected
                Button {
                    if open {
                        onPick(option.value)
                        close()
                    } else {
                        withAnimation(AudioBarMotion.spring) { open = true }
                    }
                } label: {
                    EonaIconView(icon: .symbol(option.icon), size: size * 0.44)
                        .foregroundStyle(current ? EonaColor.onAccent : EonaColor.textPrimary)
                        .frame(width: shown ? chip : 0, height: chip)
                        .background {
                            Circle()
                                .fill(EonaColor.accent)
                                .opacity(current ? 1 : 0)
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
        .padding(.horizontal, inset)
        .frame(height: size)
        // A capsule as wide as it is tall is a circle: one shape, closed or open.
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .animation(AudioBarMotion.spring, value: open)
        .animation(AudioBarMotion.spring, value: selected)
    }

    private func close() {
        withAnimation(AudioBarMotion.spring) { open = false }
    }
}

/// Opens and closes at one steady pace: under half a second, easing in and out, no bounce.
enum AudioBarMotion {
    static let spring: Animation = .smooth(duration: 0.42)
}

extension View {
    /// A HUD button making way for an open audio bar: it fades and shrinks a little where it
    /// stands. Nothing moves around it — the bar simply grows over the place it leaves.
    func audioMakesWay(_ hidden: Bool) -> some View {
        self
            .opacity(hidden ? 0 : 1)
            .scaleEffect(hidden ? 0.8 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }
}
