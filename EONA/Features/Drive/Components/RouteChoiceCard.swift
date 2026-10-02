import SwiftUI
import EonaCore

/// Choix d'itinéraire, à la sélection d'une destination : Rapide, Éco, Perso (bientôt). Un
/// panneau de verre au bas de la carte ; une option touchée est retenue, « Démarrer » lance le
/// trajet. Chaque option a ses états : calcul, prête, indisponible.
struct RouteChoiceCard: View {
    let choice: RouteChoice
    let onSelect: (RoutePreference) -> Void
    let onStart: () -> Void
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.md) {
            header
            VStack(spacing: EonaSpacing.sm) {
                RouteOptionRow(
                    kind: .fastest,
                    option: choice.fastest,
                    subtitle: choice.fastest.route.map { RouteChoiceText.fastest($0, against: choice.shortest.route) },
                    selected: choice.selected == .fastest
                ) { onSelect(.fastest) }
                RouteOptionRow(
                    kind: .shortest,
                    option: choice.shortest,
                    subtitle: choice.shortest.route.map { RouteChoiceText.eco($0, against: choice.fastest.route) },
                    selected: choice.selected == .shortest
                ) { onSelect(.shortest) }
                CustomRouteRow()
            }
            footer
        }
        .padding(EonaSpacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: EonaRadius.xxl))
        .animation(.snappy, value: choice)
        .sensoryFeedback(.selection, trigger: choice.selected)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: EonaSpacing.md) {
            VStack(alignment: .leading, spacing: EonaSpacing.hair) {
                Text("Choisis ton trajet")
                    .font(.xrCaption)
                    .foregroundStyle(EonaColor.textTertiary)
                Text(choice.destination.name)
                    .font(.xrHeadline)
                    .foregroundStyle(EonaColor.textPrimary)
                    .lineLimit(1)
                if !choice.destination.subtitle.isEmpty {
                    Text(choice.destination.subtitle)
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) {
                Image(EonaSymbol.close)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(EonaColor.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Fermer le choix de trajet")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if choice.failed {
            VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                Text("Itinéraire indisponible — vérifie la connexion et réessaie.")
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textSecondary)
                EonaButton(title: "Réessayer", variant: .secondary, fillWidth: true, action: onRetry)
            }
        } else {
            EonaButton(
                title: "Démarrer",
                systemImage: .navigation,
                loading: choice.chosenRoute == nil,
                fillWidth: true,
                action: onStart
            )
        }
    }
}

/// Une option : icône, nom, ce qu'elle apporte, temps et distance. Retenue : contour accent.
private struct RouteOptionRow: View {
    let kind: RoutePreference
    let option: RouteOption
    let subtitle: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: EonaSpacing.md) {
                RouteOptionIcon(symbol: kind.symbol, tint: kind.tint)
                VStack(alignment: .leading, spacing: EonaSpacing.hair) {
                    Text(kind.title)
                        .font(.xrHeadline)
                        .foregroundStyle(EonaColor.textPrimary)
                    Text(detail)
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.horizontal, EonaSpacing.md)
            .padding(.vertical, EonaSpacing.sm + EonaSpacing.hair)
            .background(selected ? EonaColor.accent.opacity(0.12) : Color.clear, in: .rect(cornerRadius: EonaRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: EonaRadius.lg)
                    .strokeBorder(selected ? EonaColor.accent : EonaColor.border, lineWidth: selected ? 1.5 : 1)
            }
            .contentShape(.rect(cornerRadius: EonaRadius.lg))
        }
        .buttonStyle(.plain)
        .disabled(option.route == nil)
        .opacity(option == .unavailable ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var detail: String {
        switch option {
        case .loading: "Calcul du trajet…"
        case .unavailable: "Indisponible pour l'instant"
        case .ready: subtitle ?? ""
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch option {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(minWidth: 56, alignment: .trailing)
        case .unavailable:
            EmptyView()
        case .ready(let route):
            VStack(alignment: .trailing, spacing: 0) {
                Text(RouteChoiceText.duration(route.expectedSeconds))
                    .font(.xrTitle.weight(.bold).monospacedDigit())
                    .foregroundStyle(selected ? EonaColor.accent : EonaColor.textPrimary)
                    .lineLimit(1)
                Text("\(RouteChoiceText.distance(route.distanceMeters)) · \(RouteChoiceText.arrival(route))")
                    .font(.xrCaption.monospacedDigit())
                    .foregroundStyle(EonaColor.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var accessibilityText: String {
        guard let route = option.route else { return "\(kind.title), \(detail)" }
        return "\(kind.title), \(RouteChoiceText.duration(route.expectedSeconds)), \(RouteChoiceText.distance(route.distanceMeters)), arrivée \(RouteChoiceText.arrival(route)). \(detail)"
    }
}

/// « Perso » : visible, grisée, pas encore disponible.
private struct CustomRouteRow: View {
    var body: some View {
        HStack(spacing: EonaSpacing.md) {
            RouteOptionIcon(symbol: .routeCustom, tint: EonaColor.textTertiary)
            VStack(alignment: .leading, spacing: EonaSpacing.hair) {
                Text("Perso")
                    .font(.xrHeadline)
                    .foregroundStyle(EonaColor.textSecondary)
                Text("Ton trajet, tes préférences")
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Bientôt")
                .font(.xrCaption)
                .foregroundStyle(EonaColor.textSecondary)
                .padding(.horizontal, EonaSpacing.sm)
                .padding(.vertical, EonaSpacing.xs)
                .background(EonaColor.surfaceHigh.opacity(0.6), in: .capsule)
        }
        .padding(.horizontal, EonaSpacing.md)
        .padding(.vertical, EonaSpacing.sm + EonaSpacing.hair)
        .overlay {
            RoundedRectangle(cornerRadius: EonaRadius.lg)
                .strokeBorder(EonaColor.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .opacity(0.6)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Perso, bientôt disponible")
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Icône d'option dans sa tuile teintée.
private struct RouteOptionIcon: View {
    let symbol: EonaSymbol
    let tint: Color

    var body: some View {
        Image(symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.14), in: .rect(cornerRadius: EonaRadius.md))
    }
}

private extension RoutePreference {
    var title: String {
        switch self {
        case .fastest: "Rapide"
        case .shortest: "Éco"
        }
    }

    var symbol: EonaSymbol {
        switch self {
        case .fastest: .routeFastest
        case .shortest: .routeShortest
        }
    }

    var tint: Color {
        switch self {
        case .fastest: EonaColor.accent
        case .shortest: EonaColor.success
        }
    }
}
