import SwiftUI
import EonaCore
import EonaData

/// Where the trip starts and where it goes, as two stops of one route: a ring for the departure,
/// the accent dot for the arrival, a dotted line between them. The stop being typed is a field;
/// the other one is a line that a tap turns into the field. Nothing hides behind a mode: the
/// departure is always in sight, and changing it is one tap on it.
struct RouteStopsCard: View {
    let start: Place?
    @Binding var query: String
    /// True while the departure is being chosen: its line is the field.
    let editingStart: Bool
    /// What the arrival field asks for ("Où allez-vous ?", or a saved address being set).
    let arrivalPrompt: String
    let onEditStart: () -> Void
    let onEditArrival: () -> Void
    let onResetStart: () -> Void

    @FocusState private var focus: Stop?

    private enum Stop: Hashable {
        case start
        case arrival
    }

    var body: some View {
        HStack(spacing: EonaSpacing.md) {
            spine
            VStack(spacing: 0) {
                startLine
                    .frame(height: 46)
                Rectangle()
                    .fill(EonaColor.separator)
                    .frame(height: 0.5)
                arrivalLine
                    .frame(height: 46)
            }
        }
        .padding(.leading, EonaSpacing.md)
        .padding(.trailing, EonaSpacing.xs)
        .background(EonaColor.surface.opacity(0.45), in: .rect(cornerRadius: EonaRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: EonaRadius.lg)
                .strokeBorder(EonaColor.separator, lineWidth: 0.5)
        }
        .animation(.smooth(duration: 0.3), value: editingStart)
        .animation(.smooth(duration: 0.3), value: start?.id)
        .onChange(of: editingStart) { _, starting in
            // Back to the arrival: the keyboard stays if it was open.
            if !starting, focus != nil { focus = .arrival }
        }
    }

    /// The route's spine: departure ring, three dots, arrival dot.
    private var spine: some View {
        VStack(spacing: 4) {
            Circle()
                .strokeBorder(start != nil || editingStart ? EonaColor.accent : EonaColor.textSecondary, lineWidth: 2.5)
                .frame(width: 12, height: 12)
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(EonaColor.textTertiary)
                    .frame(width: 3, height: 3)
            }
            Circle()
                .fill(EonaColor.accent)
                .frame(width: 12, height: 12)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var startLine: some View {
        if editingStart {
            field(prompt: "Adresse de départ", stop: .start)
        } else {
            HStack(spacing: EonaSpacing.sm) {
                Button(action: onEditStart) {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Départ")
                                .font(.xrCaption)
                                .foregroundStyle(EonaColor.textTertiary)
                            HStack(spacing: EonaSpacing.xs) {
                                if start == nil {
                                    EonaIconView(icon: .symbol(.recenter), size: 13)
                                        .foregroundStyle(EonaColor.accent)
                                }
                                Text(start?.name ?? "Ma position")
                                    .font(.xrCallout)
                                    .foregroundStyle(EonaColor.textPrimary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: EonaSpacing.sm)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Départ : \(start?.name ?? "ma position")")
                if start != nil {
                    // Back to the driver's own position, without typing anything.
                    Button(action: onResetStart) {
                        Image(EonaSymbol.close)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(EonaColor.textTertiary)
                            .frame(width: 30, height: 30)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Repartir de ma position")
                }
                Button(action: onEditStart) {
                    Text("Modifier")
                        .font(.xrCaption)
                        .foregroundStyle(EonaColor.accent)
                        .padding(.horizontal, EonaSpacing.sm)
                        .padding(.vertical, EonaSpacing.xs)
                        .background(EonaColor.accent.opacity(0.14), in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Modifier le départ")
            }
        }
    }

    @ViewBuilder
    private var arrivalLine: some View {
        if editingStart {
            Button(action: onEditArrival) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Arrivée")
                            .font(.xrCaption)
                            .foregroundStyle(EonaColor.textTertiary)
                        Text(arrivalPrompt)
                            .font(.xrCallout)
                            .foregroundStyle(EonaColor.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else {
            field(prompt: arrivalPrompt, stop: .arrival)
        }
    }

    /// The stop being typed. The keyboard waits for a tap on the arrival (Arthur's choice); a
    /// departure asked for opens it straight away.
    private func field(prompt: String, stop: Stop) -> some View {
        HStack(spacing: EonaSpacing.sm) {
            Image(EonaSymbol.search)
                .foregroundStyle(EonaColor.textTertiary)
            TextField(prompt, text: $query)
                .font(.xrBody)
                .foregroundStyle(EonaColor.textPrimary)
                .tint(EonaColor.accent)
                .focused($focus, equals: stop)
                .submitLabel(.search)
                .autocorrectionDisabled()
                // The departure field is asked for: it takes the keyboard as it appears.
                .onAppear { if stop == .start { focus = .start } }
            if !query.isEmpty {
                Button {
                    query = ""
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
        .padding(.trailing, EonaSpacing.xs)
    }
}

/// The first line of the list while the departure is being chosen: the driver's own position,
/// one tap away.
struct UseMyPositionRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: EonaSpacing.md) {
                EonaIconView(icon: .symbol(.recenter), size: 16)
                    .foregroundStyle(EonaColor.accent)
                    .frame(width: 32, height: 32)
                    .background(EonaColor.accent.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ma position")
                        .font(.xrBodyStrong)
                        .foregroundStyle(EonaColor.textPrimary)
                    Text("Partir d'où je suis")
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, EonaSpacing.lg)
            .padding(.vertical, EonaSpacing.sm)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Category shortcuts, scrolled sideways: each one its icon, drawn as supplied, in its square.
struct CategoryRow: View {
    let selected: PlaceCategory?
    let onSelect: (PlaceCategory) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: EonaSpacing.sm) {
                ForEach(PlaceCategory.allCases, id: \.self) { category in
                    let on = category == selected
                    Button {
                        onSelect(category)
                    } label: {
                        VStack(spacing: EonaSpacing.xs) {
                            CategorySquare(category: category, size: 46, iconSize: 24, color: on ? EonaColor.accent : category.color)
                            Text(category.label)
                                .font(.xrCaption)
                                .foregroundStyle(on ? EonaColor.accent : EonaColor.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(width: 76)
                        .padding(.vertical, EonaSpacing.xs)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(on ? 1.08 : 1)
                    .animation(.snappy, value: on)
                }
            }
            .padding(.horizontal, EonaSpacing.lg)
            .padding(.vertical, EonaSpacing.sm)
        }
        .scrollIndicators(.hidden)
    }
}

/// Which fuel's price the stations show, or "Proche uniquement" (the nearest open stations, no
/// price); the choice is remembered.
struct FuelTypeRow: View {
    let selected: FuelType
    let nearestOnly: Bool
    let onSelect: (FuelType) -> Void
    let onNearestOnly: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: EonaSpacing.sm) {
                EonaChip(label: "Proche uniquement", selected: nearestOnly) { onNearestOnly() }
                ForEach(FuelType.allCases, id: \.self) { fuel in
                    EonaChip(label: fuel.label, selected: !nearestOnly && fuel == selected) { onSelect(fuel) }
                }
            }
            .padding(.horizontal, EonaSpacing.lg)
            .padding(.vertical, EonaSpacing.xs)
        }
        .scrollIndicators(.hidden)
    }
}

/// Home and work, favourite trips, recents: what shows before anything is typed.
struct SavedPlacesList: View {
    let saved: SavedPlacesStore
    let recents: RecentsStore
    /// "Suggestions de trajets" (Confidentialité).
    let showsRecents: Bool
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
                        HStack(spacing: EonaSpacing.xs) {
                            Button {
                                onStartFavorite(trip)
                            } label: {
                                EonaListRow(
                                    title: trip.to.name,
                                    subtitle: trip.from.map { "Depuis \($0.name)" } ?? nonBlank(trip.to.subtitle),
                                    icon: .symbol(.star),
                                    tint: EonaColor.accent
                                )
                                .contentShape(.rect)
                            }
                            .buttonStyle(.borderless)
                            RowAction(symbol: .close, label: "Retirer des favoris") { saved.toggleFavorite(trip) }
                        }
                    }
                }
            }

            if showsRecents && !recents.recents.isEmpty {
                Section("Récents") {
                    ForEach(recents.recents, id: \.id) { place in
                        let favorite = saved.favorites.contains { $0.to.id == place.id || $0.id == place.id }
                        HStack(spacing: EonaSpacing.xs) {
                            Button {
                                onPick(place)
                            } label: {
                                EonaListRow(title: place.name, subtitle: nonBlank(place.subtitle), icon: .symbol(.history), tint: EonaColor.accent)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.borderless)
                            RowAction(symbol: .star, label: "Mettre en favori", tint: favorite ? EonaColor.accent : EonaColor.textTertiary) {
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
    let icon: EonaIconImage
    let place: Place?
    let onPick: (Place) -> Void
    let onSet: () -> Void

    @State private var breathing = false

    var body: some View {
        HStack(spacing: EonaSpacing.xs) {
            Button {
                if let place { onPick(place) } else { onSet() }
            } label: {
                EonaListRow(
                    title: label,
                    subtitle: place.flatMap { nonBlank($0.subtitle) } ?? place?.name,
                    icon: icon,
                    tint: EonaColor.accent
                ) {
                    if place == nil {
                        Text("Définir")
                            .font(.xrCaption)
                            .foregroundStyle(EonaColor.accent.opacity(breathing ? 1 : 0.45))
                            .padding(.horizontal, EonaSpacing.md)
                            .padding(.vertical, EonaSpacing.xs)
                            .background(EonaColor.accent.opacity(breathing ? 0.12 : 0.05), in: .capsule)
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
                EonaListRow(title: place.name, subtitle: nonBlank(place.subtitle), icon: place.kind.icon, tint: EonaColor.accent)
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
    /// Only the places open now ("Proche uniquement").
    var openOnly = false
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
            if !openOnly && !ranked.closed.isEmpty {
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
                .foregroundStyle(EonaColor.textTertiary)
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
            .foregroundStyle(EonaColor.textTertiary)
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
            HStack(alignment: .top, spacing: EonaSpacing.md) {
                CategorySquare(category: category, size: 40, iconSize: 22, color: category.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.xrBodyStrong)
                        .foregroundStyle(EonaColor.textPrimary)
                        .lineLimit(1)
                    if !location.isEmpty {
                        Text(location)
                            .font(.xrFootnote)
                            .foregroundStyle(EonaColor.textTertiary)
                            .lineLimit(1)
                    }
                    if let status {
                        StatusLine(status: status)
                    }
                    if !details.isEmpty {
                        Text(details.joined(separator: " · "))
                            .font(.xrFootnote)
                            .foregroundStyle(EonaColor.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let fuel {
                    FuelPriceTag(place: place, fuel: fuel, nowMillis: nowMillis)
                }
            }
            .padding(.vertical, EonaSpacing.xs)
            .contentShape(.rect)
        }
    }
}

/// "● Ouvert  07:00–21:00", "● Fermé  ouvre demain à 07:00": the dot and word in the state's color.
private struct StatusLine: View {
    let status: NearbyLabels.Status

    private var tint: Color {
        switch status.tone {
        case .positive: EonaColor.success
        case .warning: EonaColor.warning
        case .negative: EonaColor.danger
        case .neutral: EonaColor.textSecondary
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
                    .foregroundStyle(EonaColor.textSecondary)
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
                    .foregroundStyle(EonaColor.hazard)
            } else if let price, price.isFresh(nowMillis: nowMillis) {
                Text(price.priceLabel)
                    .font(.xrCallout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(EonaColor.textPrimary)
                if let age = price.ageLabel(nowMillis: nowMillis) {
                    Text(age)
                        .font(.xrCaption)
                        .foregroundStyle(EonaColor.textTertiary)
                }
            } else {
                Text("—")
                    .font(.xrCallout)
                    .foregroundStyle(EonaColor.textTertiary)
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
        EonaIconView(icon: .asset(category.icon), size: iconSize)
            .frame(width: size, height: size)
            .background(color, in: .rect(cornerRadius: EonaRadius.md))
    }
}

/// A small icon button at the end of a row.
private struct RowAction: View {
    let symbol: EonaSymbol
    let label: String
    var tint: Color = EonaColor.textTertiary
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
    var icon: EonaIconImage {
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
