import SwiftUI
import XRadarCore
import XRadarData

/// The trip's departure: the driver's position unless they picked somewhere else. It presses in
/// under the finger and the address slides in: a flat line read as decoration.
struct StartRow: View {
    let start: Place?
    let onEdit: () -> Void
    let onClear: () -> Void

    var body: some View {
        let simulated = start != nil
        Button(action: onEdit) {
            HStack(spacing: XRadarSpacing.sm) {
                XRadarIconView(icon: .symbol(.gps), size: 18)
                    .foregroundStyle(simulated ? XRadarColor.accent : XRadarColor.textTertiary)
                Text("Départ")
                    .font(.xrCaption)
                    .foregroundStyle(XRadarColor.textTertiary)
                // A new name pushes the old one up: both live in the stack while it slides.
                ZStack(alignment: .leading) {
                    Text(start?.name ?? "Ma position")
                        .font(.xrCallout)
                        .foregroundStyle(simulated ? XRadarColor.textPrimary : XRadarColor.textSecondary)
                        .lineLimit(1)
                        .id(start?.id ?? "")
                        .transition(.push(from: .bottom))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                if simulated {
                    // Room for the clear button laid over the row.
                    Color.clear.frame(width: 30, height: 1)
                } else {
                    Text("Changer")
                        .font(.xrCaption)
                        .foregroundStyle(XRadarColor.accent)
                }
            }
            .padding(.horizontal, XRadarSpacing.md)
            .padding(.vertical, XRadarSpacing.sm)
            .background(simulated ? XRadarColor.accent.opacity(0.12) : XRadarColor.surface.opacity(0.45), in: .rect(cornerRadius: XRadarRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: XRadarRadius.md)
                    .strokeBorder(simulated ? XRadarColor.accent : XRadarColor.border, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressScaleButtonStyle())
        .overlay(alignment: .trailing) {
            if simulated {
                RowAction(symbol: .close, label: "Repartir de ma position", action: onClear)
                    .padding(.trailing, XRadarSpacing.xs)
            }
        }
        .padding(.horizontal, XRadarSpacing.lg)
        .animation(.smooth, value: start?.id)
    }
}

/// Category shortcuts, scrolled sideways: each one its icon, drawn as supplied, in its square.
struct CategoryRow: View {
    let selected: PlaceCategory?
    let onSelect: (PlaceCategory) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: XRadarSpacing.sm) {
                ForEach(PlaceCategory.allCases, id: \.self) { category in
                    let on = category == selected
                    Button {
                        onSelect(category)
                    } label: {
                        VStack(spacing: XRadarSpacing.xs) {
                            CategorySquare(category: category, size: 46, iconSize: 24, color: on ? XRadarColor.accent : category.color)
                            Text(category.label)
                                .font(.xrCaption)
                                .foregroundStyle(on ? XRadarColor.accent : XRadarColor.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(width: 76)
                        .padding(.vertical, XRadarSpacing.xs)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(on ? 1.08 : 1)
                    .animation(.snappy, value: on)
                }
            }
            .padding(.horizontal, XRadarSpacing.lg)
            .padding(.vertical, XRadarSpacing.sm)
        }
        .scrollIndicators(.hidden)
    }
}

/// Which fuel's price the stations show; the choice is remembered.
struct FuelTypeRow: View {
    let selected: FuelType
    let onSelect: (FuelType) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: XRadarSpacing.sm) {
                ForEach(FuelType.allCases, id: \.self) { fuel in
                    XRadarChip(label: fuel.label, selected: fuel == selected) { onSelect(fuel) }
                }
            }
            .padding(.horizontal, XRadarSpacing.lg)
            .padding(.vertical, XRadarSpacing.xs)
        }
        .scrollIndicators(.hidden)
    }
}

/// Home and work, favourite trips, recents: what shows before anything is typed.
struct SavedPlacesList: View {
    let saved: SavedPlacesStore
    let recents: RecentsStore
    let start: Place?
    let onPick: (Place) -> Void
    let onSetHome: () -> Void
    let onSetWork: () -> Void
    let onStartFavorite: (FavoriteTrip) -> Void

    var body: some View {
        List {
            Section("Adresses") {
                SavedRow(label: "Maison", icon: .symbol(.home), place: saved.home, onPick: onPick, onSet: onSetHome)
                SavedRow(label: "Travail", icon: .symbol(.flag), place: saved.work, onPick: onPick, onSet: onSetWork)
            }

            if !saved.favorites.isEmpty {
                Section("Trajets favoris") {
                    ForEach(saved.favorites, id: \.id) { trip in
                        HStack(spacing: XRadarSpacing.xs) {
                            Button {
                                onStartFavorite(trip)
                            } label: {
                                XRadarListRow(
                                    title: trip.to.name,
                                    subtitle: trip.from.map { "Depuis \($0.name)" } ?? nonBlank(trip.to.subtitle),
                                    icon: .symbol(.star),
                                    tint: XRadarColor.accent
                                )
                                .contentShape(.rect)
                            }
                            .buttonStyle(.borderless)
                            RowAction(symbol: .close, label: "Retirer des favoris") { saved.toggleFavorite(trip) }
                        }
                    }
                }
            }

            if !recents.recents.isEmpty {
                Section("Récents") {
                    ForEach(recents.recents, id: \.id) { place in
                        let favorite = saved.favorites.contains { $0.to.id == place.id || $0.id == place.id }
                        HStack(spacing: XRadarSpacing.xs) {
                            Button {
                                onPick(place)
                            } label: {
                                XRadarListRow(title: place.name, subtitle: nonBlank(place.subtitle), icon: .symbol(.history), tint: XRadarColor.accent)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.borderless)
                            RowAction(symbol: .star, label: "Mettre en favori", tint: favorite ? XRadarColor.accent : XRadarColor.textTertiary) {
                                saved.toggleFavorite(FavoriteTrip(to: place, from: start))
                            }
                            RowAction(symbol: .close, label: "Retirer des récents") { recents.remove(place.id) }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }
}

/// Home / work. An empty one breathes gently and says "Définir": otherwise nothing suggests the
/// row does anything.
private struct SavedRow: View {
    let label: String
    let icon: XRadarIconImage
    let place: Place?
    let onPick: (Place) -> Void
    let onSet: () -> Void

    @State private var breathing = false

    var body: some View {
        HStack(spacing: XRadarSpacing.xs) {
            Button {
                if let place { onPick(place) } else { onSet() }
            } label: {
                XRadarListRow(
                    title: label,
                    subtitle: place.flatMap { nonBlank($0.subtitle) } ?? place?.name,
                    icon: icon,
                    tint: XRadarColor.accent
                ) {
                    if place == nil {
                        Text("Définir")
                            .font(.xrCaption)
                            .foregroundStyle(XRadarColor.accent.opacity(breathing ? 1 : 0.45))
                            .padding(.horizontal, XRadarSpacing.md)
                            .padding(.vertical, XRadarSpacing.xs)
                            .background(XRadarColor.accent.opacity(breathing ? 0.12 : 0.05), in: .capsule)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(PressScaleButtonStyle())
            if place != nil {
                RowAction(symbol: .settings, label: "Changer l'adresse", action: onSet)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

/// Addresses found by the text search, in the order they came.
struct ResultList: View {
    let results: [Place]
    let onPick: (Place) -> Void

    var body: some View {
        List(results, id: \.id) { place in
            Button {
                onPick(place)
            } label: {
                XRadarListRow(title: place.name, subtitle: nonBlank(place.subtitle), icon: place.kind.icon, tint: XRadarColor.accent)
                    .contentShape(.rect)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }
}

/// The nearby places as NearbyPicker ranks them: open ones first (with a fuel, those showing a
/// price for it, then "Sans prix récent"), and those closed right now under their own heading,
/// dimmed. The sources are credited at the bottom.
struct NearbyList: View {
    let places: [Place]
    let category: PlaceCategory
    let fuel: FuelType?
    let onPick: (Place) -> Void

    var body: some View {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let ranked = NearbyPicker.pick(places, category: category, fuel: fuel, nowMillis: now)
        // A stable split of a list already in order: nothing moves inside a group.
        let priced = fuel.map { fuel in ranked.open.filter { $0.showsFuelPrice(fuel, nowMillis: now) } } ?? ranked.open
        let unpriced = fuel.map { fuel in ranked.open.filter { !$0.showsFuelPrice(fuel, nowMillis: now) } } ?? []
        List {
            ForEach(priced, id: \.id) { place in
                row(place, now: now, closed: false)
            }
            if !unpriced.isEmpty {
                Section {
                    ForEach(unpriced, id: \.id) { place in
                        row(place, now: now, closed: false)
                    }
                } header: {
                    if !priced.isEmpty { sectionLabel("Sans prix récent") }
                }
            }
            if !ranked.closed.isEmpty {
                Section {
                    ForEach(ranked.closed, id: \.id) { place in
                        row(place, now: now, closed: true)
                    }
                } header: {
                    sectionLabel("Fermés en ce moment")
                }
            }
            Text(fuel != nil
                ? "Prix officiels : prix-carburants.gouv.fr. Seuls les prix mis à jour depuis moins de 48 h sont affichés. Lieux et horaires : © contributeurs OpenStreetMap."
                : "Lieux et horaires : © contributeurs OpenStreetMap.")
                .font(.xrFootnote)
                .foregroundStyle(XRadarColor.textTertiary)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private func row(_ place: Place, now: Int, closed: Bool) -> some View {
        NearbyRow(place: place, category: category, fuel: fuel, nowMillis: now, onPick: onPick)
            .opacity(closed ? 0.6 : 1)
            .listRowBackground(Color.clear)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.xrCaption)
            .foregroundStyle(XRadarColor.textTertiary)
    }
}

/// One nearby place: its category square, name, how far and where, whether it is open (today's
/// hours or when it opens), and what matters for its kind. The official price sits on the right
/// for fuel.
private struct NearbyRow: View {
    let place: Place
    let category: PlaceCategory
    let fuel: FuelType?
    let nowMillis: Int
    let onPick: (Place) -> Void

    var body: some View {
        let status = NearbyLabels.status(place.nearby?.hours, nowMillis: nowMillis)
        let details = NearbyLabels.details(place)
        let location = [place.distanceMeters.map { NearbyLabels.distance($0) }, nonBlank(place.subtitle)]
            .compactMap { $0 }
            .joined(separator: " · ")
        Button {
            onPick(place)
        } label: {
            HStack(alignment: .top, spacing: XRadarSpacing.md) {
                CategorySquare(category: category, size: 40, iconSize: 22, color: category.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.xrBodyStrong)
                        .foregroundStyle(XRadarColor.textPrimary)
                        .lineLimit(1)
                    if !location.isEmpty {
                        Text(location)
                            .font(.xrFootnote)
                            .foregroundStyle(XRadarColor.textTertiary)
                            .lineLimit(1)
                    }
                    if let status {
                        StatusLine(status: status)
                    }
                    if !details.isEmpty {
                        Text(details.joined(separator: " · "))
                            .font(.xrFootnote)
                            .foregroundStyle(XRadarColor.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let fuel {
                    FuelPriceTag(place: place, fuel: fuel, nowMillis: nowMillis)
                }
            }
            .padding(.vertical, XRadarSpacing.xs)
            .contentShape(.rect)
        }
    }
}

/// "● Ouvert  07:00–21:00", "● Fermé  ouvre demain à 07:00": the dot and word in the state's color.
private struct StatusLine: View {
    let status: NearbyLabels.Status

    private var tint: Color {
        switch status.tone {
        case .positive: XRadarColor.success
        case .warning: XRadarColor.warning
        case .negative: XRadarColor.danger
        case .neutral: XRadarColor.textSecondary
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(status.text)
                .font(.xrFootnote.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
            if let detail = status.detail {
                Text(detail)
                    .font(.xrFootnote)
                    .foregroundStyle(XRadarColor.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

/// The official price of [fuel] at this station: "2,283 €" over its age, "Rupture" when the
/// station is out of it, "—" without a price younger than 48 h.
private struct FuelPriceTag: View {
    let place: Place
    let fuel: FuelType
    let nowMillis: Int

    var body: some View {
        let price = place.fuel?.prices.first(where: { $0.type == fuel })
        VStack(alignment: .trailing, spacing: 0) {
            if let price, price.outOfStock {
                Text("Rupture")
                    .font(.xrCallout)
                    .foregroundStyle(XRadarColor.hazard)
            } else if let price, price.isFresh(nowMillis: nowMillis) {
                Text(price.priceLabel)
                    .font(.xrCallout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(XRadarColor.textPrimary)
                if let age = price.ageLabel(nowMillis: nowMillis) {
                    Text(age)
                        .font(.xrCaption)
                        .foregroundStyle(XRadarColor.textTertiary)
                }
            } else {
                Text("—")
                    .font(.xrCallout)
                    .foregroundStyle(XRadarColor.textTertiary)
            }
        }
    }
}

/// A category's icon, drawn as supplied, on its colored square.
private struct CategorySquare: View {
    let category: PlaceCategory
    let size: CGFloat
    let iconSize: CGFloat
    let color: Color

    var body: some View {
        XRadarIconView(icon: .asset(category.icon), size: iconSize)
            .frame(width: size, height: size)
            .background(color, in: .rect(cornerRadius: XRadarRadius.md))
    }
}

/// A small icon button at the end of a row.
private struct RowAction: View {
    let symbol: XRadarSymbol
    let label: String
    var tint: Color = XRadarColor.textTertiary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }
}

/// Presses in under the finger.
private struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

private extension PlaceKind {
    var icon: XRadarIconImage {
        switch self {
        case .home: .symbol(.home)
        case .work: .symbol(.flag)
        case .favorite: .symbol(.star)
        case .recent: .symbol(.history)
        case .result: .symbol(.mapPin)
        }
    }
}

/// Nil for an empty or blank text, so a row shows no empty line.
private func nonBlank(_ text: String) -> String? {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
}
