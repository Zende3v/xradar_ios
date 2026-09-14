import SwiftUI
import XRadarCore

/// Every token and component on one screen, to check them on an iPhone (light and dark, glass
/// over a map-like background). Reached from the verification screen.
struct DesignSystemGallery: View {
    @State private var query = ""
    @State private var voice = true
    @State private var fuel = FuelType.gazole
    @State private var loading = false

    private let swatches: [(String, Color)] = [
        ("canvas", XRadarColor.canvas), ("surface", XRadarColor.surface),
        ("elevated", XRadarColor.surfaceElevated), ("high", XRadarColor.surfaceHigh),
        ("texte", XRadarColor.textPrimary), ("secondaire", XRadarColor.textSecondary),
        ("tertiaire", XRadarColor.textTertiary), ("accent", XRadarColor.accent),
        ("succès", XRadarColor.success), ("attention", XRadarColor.warning),
        ("danger", XRadarColor.danger), ("info", XRadarColor.info),
        ("zone", XRadarColor.controlZone), ("danger route", XRadarColor.hazard),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XRadarSpacing.xxl) {
                section("Couleurs") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: XRadarSpacing.md)], spacing: XRadarSpacing.md) {
                        ForEach(swatches, id: \.0) { name, color in
                            VStack(spacing: XRadarSpacing.xs) {
                                RoundedRectangle(cornerRadius: XRadarRadius.md)
                                    .fill(color)
                                    .frame(height: 44)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: XRadarRadius.md).strokeBorder(XRadarColor.borderStrong)
                                    }
                                Text(name)
                                    .font(.xrCaption)
                                    .foregroundStyle(XRadarColor.textSecondary)
                            }
                        }
                    }
                }

                section("Typographie") {
                    VStack(alignment: .leading, spacing: XRadarSpacing.xs) {
                        Text("88").font(.xrDisplayHero)
                        Text("Display 40").font(.xrDisplay)
                        Text("Title large 28").font(.xrTitleLarge)
                        Text("Title 22").font(.xrTitle)
                        Text("Headline 17").font(.xrHeadline)
                        Text("Body 17 — Rue de la Paix").font(.xrBody)
                        Text("Callout 16").font(.xrCallout)
                        Text("Footnote 13").font(.xrFootnote)
                        Text("CAPTION 12").font(.xrCaption)
                        Text("12:45 · 1,2 km · 130").font(.xrNumeric)
                    }
                    .foregroundStyle(XRadarColor.textPrimary)
                }

                section("Boutons") {
                    VStack(spacing: XRadarSpacing.md) {
                        XRadarButton(title: "Démarrer", systemImage: .navigation, fillWidth: true) {}
                        XRadarButton(title: "Itinéraire bis", variant: .secondary, fillWidth: true) {}
                        XRadarButton(title: "Plus tard", variant: .ghost, fillWidth: true) {}
                        XRadarButton(title: "Supprimer le compte", variant: .destructive, fillWidth: true) {}
                        XRadarButton(title: "Chargement", loading: loading, fillWidth: true) {
                            loading.toggle()
                        }
                    }
                }

                section("Sur la carte") {
                    ZStack(alignment: .top) {
                        mapLikeBackground
                        VStack(spacing: XRadarSpacing.md) {
                            XRadarSearchField(text: $query)
                            HStack(spacing: XRadarSpacing.sm) {
                                ForEach(FuelType.allCases.prefix(4), id: \.self) { type in
                                    XRadarChip(label: type.label, selected: type == fuel) { fuel = type }
                                }
                            }
                            Spacer(minLength: 0)
                            HStack {
                                XRadarIconButton(icon: .symbol(.recenter), label: "Recentrer", size: 56, tint: XRadarColor.accent) {}
                                Spacer()
                                XRadarIconButton(icon: .asset(.report), label: "Signaler", size: 56, tint: XRadarColor.warning) {}
                            }
                            HStack(spacing: XRadarSpacing.md) {
                                XRadarGlowIcon(icon: .asset(.radar), tint: XRadarColor.radarFixed, size: 28)
                                VStack(alignment: .leading) {
                                    Text("Radar fixe").font(.xrHeadline)
                                    Text("450 m · limité à 80").font(.xrFootnote).foregroundStyle(XRadarColor.textSecondary)
                                }
                                Spacer()
                                XRadarBadge(text: "Fiable", color: XRadarColor.success)
                            }
                            .xrGlassPanel()
                        }
                        .padding(XRadarSpacing.md)
                    }
                    .frame(height: 420)
                    .clipShape(.rect(cornerRadius: XRadarRadius.xl))
                }

                section("Liste") {
                    VStack(spacing: 0) {
                        XRadarListRow(title: "Voix", subtitle: "Guidage et alertes", icon: .symbol(.volumeOn), tint: XRadarColor.accent) {
                            Toggle("Voix", isOn: $voice).labelsHidden().tint(XRadarColor.accent)
                        }
                        .padding(XRadarSpacing.md)
                        Divider().padding(.leading, 54)
                        XRadarListRow(title: "Statistiques", icon: .symbol(.stats), tint: XRadarColor.info) {
                            Image(XRadarSymbol.chevronRight).foregroundStyle(XRadarColor.textTertiary)
                        }
                        .padding(XRadarSpacing.md)
                    }
                    .xrCard(padding: 0)
                }

                section("Catégories") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: XRadarSpacing.md) {
                        ForEach(PlaceCategory.allCases, id: \.self) { category in
                            VStack(spacing: XRadarSpacing.xs) {
                                XRadarIconView(icon: .asset(category.icon), size: 24)
                                    .frame(width: 46, height: 46)
                                    .background(category.color, in: .rect(cornerRadius: XRadarRadius.md))
                                Text(category.label).font(.xrCaption).foregroundStyle(XRadarColor.textSecondary)
                            }
                        }
                    }
                }

                section("Icônes XRadar") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], spacing: XRadarSpacing.md) {
                        ForEach(XRadarAsset.allCases.filter { !$0.rawValue.hasPrefix("ic_place_") }, id: \.self) { asset in
                            XRadarIconView(icon: .asset(asset), size: 28)
                                .foregroundStyle(XRadarColor.textPrimary)
                                .frame(width: 52, height: 52)
                                .background(XRadarColor.surfaceElevated, in: .rect(cornerRadius: XRadarRadius.sm))
                        }
                    }
                }

                section("États") {
                    XRadarMessageState(
                        icon: .symbol(.gps),
                        title: "Activer la localisation",
                        message: "x_radar utilise ta position pour la navigation en temps réel et les alertes radars sur ta route.",
                        tint: XRadarColor.accent,
                        primaryLabel: "Autoriser la localisation",
                        onPrimary: {},
                        secondaryLabel: "Plus tard",
                        onSecondary: {}
                    )
                    .frame(height: 440)
                    .xrCard(padding: 0)
                    XRadarLoadingState(label: "Recherche autour de toi…")
                        .frame(height: 120)
                }
            }
            .padding(XRadarSpacing.lg)
        }
        .background(XRadarColor.canvas)
        .navigationTitle("Design system")
    }

    private var mapLikeBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.32, blue: 0.42), Color(red: 0.55, green: 0.62, blue: 0.48), Color(red: 0.86, green: 0.78, blue: 0.62)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Path { path in
                path.move(to: CGPoint(x: -20, y: 300))
                path.addCurve(to: CGPoint(x: 420, y: 120), control1: CGPoint(x: 120, y: 180), control2: CGPoint(x: 260, y: 360))
            }
            .stroke(XRadarColor.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
            Text("Carte")
                .font(.xrDisplay)
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: XRadarSpacing.md) {
            Text(title.uppercased())
                .font(.xrCaption)
                .foregroundStyle(XRadarColor.textTertiary)
            content()
        }
    }
}

#Preview {
    NavigationStack { DesignSystemGallery() }
}
