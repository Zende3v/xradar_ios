import SwiftUI
import EonaCore
import EonaData

/// The driving HUD, like the Android DriveScreen: the map; on top the search bar or the next
/// maneuver, the stop button and the menu, then the music banner; at the bottom the alerts, the
/// sound and voice buttons and the dock; the map controls on the right.
struct DriveScreen: View {
    let services: AppServices
    let model: DriveModel
    var onOpenSearch: () -> Void
    var onOpenMenu: () -> Void
    /// A blocked action (account blocked, a guest's limit of the day, a members' feature): the
    /// offers show, saying why.
    var onBlocked: (PaywallReason) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var following = true
    @State private var reportOpen = false
    @State private var limitReportOpen = false
    @State private var pendingDelete: String?
    @State private var dockOpen = false
    @State private var shareOpen = false

    /// Arrêter la navigation pendant un trajet en groupe, c'est quitter le groupe : on demande.
    @State private var confirmStop = false
    /// Which audio bar is open, if any: only one at a time, and it hides its neighbours.
    @State private var audioMenu: AudioMenu?
    @State private var heights = Heights(safe: 700, screen: 800)
    @State private var aboveDockHeight: CGFloat = 0

    var body: some View {
        let state = model.state
        let restricted = services.account.account?.isRestricted == true
        let onReportTap: ((String) -> Void)? = services.account.role == .admin ? { pendingDelete = $0 } : nil
        // Day or night ("Thème général", on the window): the map draws like the HUD over it.
        let mapDark = colorScheme == .dark

        ZStack {
            DriveMapView(
                location: state.location,
                content: state.map,
                following: following,
                speedLimitKmh: state.speedLimitKmh,
                dark: mapDark,
                onUserGesture: { following = false },
                onReportTap: onReportTap,
                group: model.groupMap
            )
            .ignoresSafeArea()

            // Une barre audio ouverte se referme dès qu'on touche ailleurs.
            if audioMenu != nil {
                Color.clear
                    .contentShape(.rect)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(AudioBarMotion.spring) { audioMenu = nil } }
            }

            MapCredits()
            topBar(state, restricted: restricted)
            bottomColumn(state, restricted: restricted, dockOpen: dockOpen)
            mapControls(restricted: restricted, dockOpen: dockOpen)
        }
        .onGeometryChange(for: Heights.self) { proxy in
            Heights(safe: proxy.size.height, screen: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
        } action: { heights = $0 }
        .sheet(isPresented: $reportOpen) {
            ReportSheet(role: services.account.role) { draft in
                model.report(draft)
                reportOpen = false
            }
        }
        .sheet(isPresented: $shareOpen) {
            TripShareSheet(model: model) { shareOpen = false }
                // The sheet keeps the system's Liquid Glass, like the rest of the HUD's sheets.
                .presentationDetents([.medium, .large])
        }

        .confirmationDialog("Arrêter la navigation ?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Arrêter et quitter le groupe", role: .destructive) {
                services.activeTrip.clear()
            }
            Button("Continuer", role: .cancel) {}
        } message: {
            Text("Tu quitteras aussi le trajet en groupe. Les autres continuent sans toi.")
        }
        .sheet(isPresented: $limitReportOpen) {
            SpeedLimitSheet(currentKmh: model.state.speedLimitKmh) { kmh in
                model.reportSpeedLimit(kmh)
                limitReportOpen = false
            }
        }
        .alert("Supprimer ce signalement ?", isPresented: deleteConfirmation) {
            Button("Annuler", role: .cancel) { pendingDelete = nil }
            Button("Supprimer", role: .destructive) {
                if let id = pendingDelete { model.deleteReport(id) }
                pendingDelete = nil
            }
        } message: {
            Text("Modération admin — action définitive.")
        }
        .task {
            model.start()
            services.music.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from Réglages or Music: access and the track may have changed meanwhile.
            if phase == .active { services.music.refresh() }
        }
    }

    // MARK: Top

    private func topBar(_ state: DriveState, restricted: Bool) -> some View {
        VStack(spacing: EonaSpacing.sm) {
            HStack(spacing: EonaSpacing.sm) {
                ZStack {
                    if let guidance = state.guidance {
                        GuidanceBanner(instruction: guidance)
                            .transition(.opacity)
                    } else if state.trip == nil {
                        HudSearchBar {
                            if restricted {
                                onBlocked(.restricted)
                            } else if limits?.tripsLeft() == 0 {
                                onBlocked(.tripLimit)
                            } else {
                                onOpenSearch()
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)

                // While navigating, a one-tap stop.
                if state.trip != nil {
                    EonaIconButton(icon: .symbol(.close), label: "Arrêter la navigation", size: 48) {
                        if model.groupLive {
                            confirmStop = true
                        } else {
                            services.activeTrip.clear()
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                EonaIconButton(icon: .symbol(.menu), label: "Menu", size: 48, action: onOpenMenu)
            }

            // Under the search bar (or the guidance), in the flow: it never covers either.
            if let notice = model.fasterNotice {
                FasterRouteBanner(notice: notice)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let notice = model.groupNotice {
                GroupNoticeBanner(text: notice) { model.acknowledgeGroupNotice() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if model.musicOpen {
                MusicBanner(player: services.music)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            // The others of the group, one chip each: a tap follows them on the map.
            if model.groupLive {
                GroupStrip(
                    model: model,
                    onOverview: {
                        following = false
                        model.showWholeGroup()
                    },
                    onFocus: { id in
                        model.focusGroup(on: id)
                        following = true
                    }
                )
            }
        }
        .padding(.horizontal, EonaSpacing.lg)
        .padding(.vertical, EonaSpacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.25), value: state.guidance == nil)
        .animation(.easeInOut(duration: 0.25), value: state.trip == nil)
        .animation(.snappy, value: model.musicOpen)
        .animation(.snappy, value: model.fasterNotice)
        .animation(.snappy, value: model.groupNotice)
        .animation(.snappy, value: model.groupLive)
    }

    // MARK: Bottom

    private func bottomColumn(_ state: DriveState, restricted: Bool, dockOpen: Bool) -> some View {
        // Alerts swiped away stay off the HUD for a while (still live for the voice).
        let shownAlerts = state.alerts.filter { !model.dismissedAlerts.contains($0.key) }
        let showAlerts = !shownAlerts.isEmpty && !restricted
        let hasAbove = showAlerts || state.routeError || model.slowdownPrompt != nil || !dockOpen
        let expanded = min(
            heights.screen * 0.8,
            heights.safe - 2 * EonaSpacing.lg - aboveDockHeight - (hasAbove ? EonaSpacing.md : 0)
        )
        return VStack(spacing: 0) {
            VStack(spacing: EonaSpacing.md) {
                if showAlerts {
                    AlertStack(
                        alerts: shownAlerts,
                        onDismiss: { model.dismissAlert($0) },
                        canVote: { canVote($0) },
                        onVote: { alert, confirm in
                            if let id = alert.id { model.vote(id, confirm: confirm) }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if state.routeError {
                    RouteErrorBanner()
                        .transition(.opacity)
                }
                if model.slowdownPrompt != nil {
                    SlowdownPromptCard { model.answerSlowdown($0) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let arrival = model.arrival {
                    ArrivalCard(arrival: arrival) { model.dismissArrival() }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if model.finishedGroup != nil {
                    GroupFinishCard(model: model)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                // Alert sound and voice, reachable without opening the dock, on the left so the
                // report button stays on the right.
                if !dockOpen {
                    // Each audio bar keeps a button's width in the row and grows to the right over
                    // its neighbours, which fade where they stand: nothing slides, nothing jumps.
                    HStack(spacing: EonaSpacing.sm) {
                        alertSoundButton
                            .frame(width: 48, alignment: .leading)
                            .zIndex(audioMenu == .sound ? 1 : 0)
                        voiceButton
                            .frame(width: 48, alignment: .leading)
                            .zIndex(audioMenu == .voice ? 1 : 0)
                            .audioMakesWay(audioMenu == .sound)
                        if state.trip != nil {
                            shareButton.audioMakesWay(audioMenu != nil)
                        }
                        if model.inGroup {
                            groupButton.audioMakesWay(audioMenu != nil)
                        }
                        Spacer(minLength: 0)
                    }
                    .animation(AudioBarMotion.spring, value: audioMenu)
                    .transition(.opacity)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { aboveDockHeight = $0 }

            if hasAbove {
                Color.clear.frame(height: EonaSpacing.md)
            }

            DriveDock(
                speedKmh: state.speedKmh,
                limitKmh: state.speedLimitKmh,
                status: state.speedStatus,
                searching: state.isSearchingGps,
                trip: state.trip,
                maxHeight: expanded,
                preferences: services.preferences,
                // A position is needed to report a limit.
                onLimitClick: state.isSearchingGps ? nil : {
                    if restricted { onBlocked(.restricted) } else { limitReportOpen = true }
                },
                onOpenChange: { self.dockOpen = $0 }
            )
        }
        .padding(EonaSpacing.lg)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .animation(.snappy, value: showAlerts)
        .animation(.snappy, value: state.routeError)
        .animation(.snappy, value: model.slowdownPrompt)
        .animation(.easeInOut(duration: 0.2), value: dockOpen)
    }

    /// Only crowd reports, close ahead, and one voice per driver.
    private func canVote(_ alert: RoadAlert) -> Bool {
        guard let id = alert.id else { return false }
        return alert.lastReportedLabel != nil
            && !model.votedReports.contains(id)
            && alert.distanceMeters <= AlertsAhead.voteDistanceMeters
    }

    /// Alert sound: silent, sound, sound and vibration — the three laid side by side.
    private var alertSoundButton: some View {
        let prefs = services.preferences.alerts
        let mode: AlertSoundMode = !prefs.sound ? .silent : (prefs.vibration ? .soundAndBuzz : .sound)
        return AudioOptionBar(
            options: [
                AudioOption(value: AlertSoundMode.silent, icon: .bellOff, label: "Silencieux"),
                AudioOption(value: AlertSoundMode.sound, icon: .bell, label: "Son"),
                AudioOption(value: AlertSoundMode.soundAndBuzz, icon: .bellRinging, label: "Son et vibration"),
            ],
            selected: mode,
            label: "Son des alertes",
            open: Binding(get: { audioMenu == .sound }, set: { audioMenu = $0 ? .sound : nil })
        ) { picked in
            services.preferences.updateAlerts { alerts in
                alerts.sound = picked != .silent
                alerts.vibration = picked == .soundAndBuzz
            }
        }
    }

    /// Spoken guidance and alert announcements, on or off.
    /// "Trajet en groupe", quand il y en a un : le groupe, son code, ce que je partage. Les
    /// autres, eux, sont sur la carte. Le point dit si je partage ma position ou non.
    private var groupButton: some View {
        EonaIconButton(icon: .symbol(.people), label: "Trajet en groupe", size: 48) {
            shareOpen = true
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(model.groupSharing ? EonaColor.accent : EonaColor.textTertiary)
                .frame(width: 10, height: 10)
                .offset(x: 2, y: -2)
        }
    }

    /// "Partager mon trajet", pendant un trajet seulement : le lien s'ouvre dans la feuille.
    private var shareButton: some View {
        EonaIconButton(icon: .asset(.share), label: "Partager mon trajet", size: 48) {
            shareOpen = true
        }
        .overlay(alignment: .topTrailing) {
            // Un partage en cours se voit d'un coup d'œil.
            if model.tripShare != nil {
                Circle()
                    .fill(EonaColor.accent)
                    .frame(width: 10, height: 10)
                    .offset(x: 2, y: -2)
            }
        }
    }

    private var voiceButton: some View {
        let voice = services.preferences.alerts.voice
        return AudioOptionBar(
            options: [
                AudioOption(value: false, icon: .volumeOff, label: "Voix coupée"),
                AudioOption(value: true, icon: .volumeOn, label: "Voix activée"),
            ],
            selected: voice,
            label: "Annonces vocales",
            open: Binding(get: { audioMenu == .voice }, set: { audioMenu = $0 ? .voice : nil })
        ) { picked in
            services.preferences.updateAlerts { $0.voice = picked }
        }
    }

    /// Which of the two audio bars is open.
    private enum AudioMenu {
        case sound
        case voice
    }

    /// What the alert-sound bar offers, in order.
    private enum AlertSoundMode {
        case silent
        case sound
        case soundAndBuzz
    }

    // MARK: Map controls

    /// Recenter, music and report share one size; they step aside while the dock is pulled up.
    private func mapControls(restricted: Bool, dockOpen: Bool) -> some View {
        ZStack {
            if !dockOpen {
                GlassEffectContainer(spacing: EonaSpacing.sm) {
                    VStack(spacing: EonaSpacing.sm) {
                        if !following || model.groupFocus != nil {
                            EonaIconButton(icon: .symbol(.recenter), label: "Recentrer", size: 56, tint: EonaColor.accent) {
                                model.focusGroup(on: nil)
                                following = true
                            }
                        }
                        // The music shortcut is for members; an open banner can always be closed.
                        EonaIconButton(icon: .symbol(.music), label: model.musicOpen ? "Fermer la musique" : "Musique", size: 56) {
                            if model.musicOpen || (!restricted && services.account.role != .guest) {
                                model.toggleMusic()
                            } else {
                                onBlocked(restricted ? .restricted : .music)
                            }
                        }
                        // The main crowdsourcing action: signal something on the road.
                        // Neutral glass and a grey warning triangle, as drawn in the new asset.
                        EonaIconButton(icon: .symbol(.warning), label: "Signaler", size: 56, tint: EonaColor.textSecondary) {
                            if restricted {
                                onBlocked(.restricted)
                            } else if limits?.reportsLeft() == 0 {
                                onBlocked(.reportLimit)
                            } else {
                                reportOpen = true
                            }
                        }
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.trailing, EonaSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .animation(.snappy, value: following)
        .animation(.easeInOut(duration: 0.2), value: dockOpen)
    }

    /// A guest's limits of the day; nil for members, who have none.
    private var limits: DailyLimits? {
        services.account.account?.limits
    }

    private var deleteConfirmation: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }
}

/// The safe-area height and the full screen height, for the dock's reach.
nonisolated private struct Heights: Equatable, Sendable {
    let safe: CGFloat
    let screen: CGFloat
}

private struct HudSearchBar: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: EonaSpacing.sm) {
                Image(EonaSymbol.search)
                    .font(.system(size: 17, weight: .semibold))
                Text("Où allez-vous ?")
                    .font(.xrBody)
                Spacer(minLength: 0)
            }
            .foregroundStyle(EonaColor.textSecondary)
            .padding(.horizontal, EonaSpacing.lg)
            .frame(height: 48)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// The Plans credits, always on the map but as discreet as can be: a tiny line in the
/// home-indicator strip, opening Apple's legal notice.
private struct MapCredits: View {
    var body: some View {
        Link(destination: LegalScreen.appleData) {
            HStack(spacing: 2) {
                Image(EonaSymbol.appleLogo)
                Text("Plans · Mentions légales")
            }
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(EonaColor.textSecondary.opacity(0.6))
        }
        .accessibilityLabel("Plans, mentions légales")
        .padding(.leading, EonaSpacing.xl)
        .padding(.bottom, EonaSpacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .ignoresSafeArea(edges: .bottom)
    }
}

/// A faster way around the traffic was taken: the time it saves, for a few seconds; or the way
/// around a closed road.
/// A word about the group — cancelled by its host, left on stopping — a few seconds.
private struct GroupNoticeBanner: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: EonaSpacing.sm) {
            Image(systemName: EonaSymbol.people.rawValue)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(EonaColor.accent)
            Text(text)
                .font(.xrLabel)
                .foregroundStyle(EonaColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(EonaSpacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: EonaRadius.lg))
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
    }
}

private struct FasterRouteBanner: View {
    let notice: FasterRouteNotice

    var body: some View {
        HStack(spacing: EonaSpacing.sm) {
            Image(EonaSymbol.fasterRoute)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(EonaColor.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.closedRoad ? "Route fermée devant" : "Itinéraire plus rapide")
                    .font(.xrLabel)
                    .foregroundStyle(EonaColor.textPrimary)
                Text(subtitle)
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(EonaSpacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: EonaRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: EonaRadius.lg).strokeBorder(EonaColor.success, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if notice.closedRoad { return "Nouvel itinéraire pour la contourner" }
        return notice.gainMinutes > 1 ? "\(notice.gainMinutes) min gagnées avec le trafic" : "1 min gagnée avec le trafic"
    }
}

/// The destination is reached: a round check that lands with a bounce, the place, and what the
/// trip came to. It goes on its own after a few seconds, or on "Terminé".
private struct ArrivalCard: View {
    let arrival: TripArrival
    let onDismiss: () -> Void

    @State private var landed = false

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.md) {
            HStack(spacing: EonaSpacing.md) {
                Image(EonaSymbol.check)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(EonaColor.success)
                    .frame(width: 48, height: 48)
                    .background(EonaColor.success.opacity(0.18), in: .circle)
                    .scaleEffect(landed ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vous êtes arrivé")
                        .font(.xrHeadline)
                        .foregroundStyle(EonaColor.textPrimary)
                    Text(arrival.toLabel)
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: EonaSpacing.lg) {
                figure("Durée", Self.duration(arrival.durationSeconds))
                figure("Distance", Self.distance(arrival.distanceMeters))
                if arrival.alertsCount > 0 {
                    figure("Alertes", "\(arrival.alertsCount)")
                }
                Spacer(minLength: 0)
            }
            EonaButton(title: "Terminé", variant: .secondary, fillWidth: true) { onDismiss() }
        }
        .padding(EonaSpacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: EonaRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: EonaRadius.lg).strokeBorder(EonaColor.success, lineWidth: 1)
        }
        .task(id: arrival.id) {
            landed = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { landed = true }
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.xrBodyStrong)
                .foregroundStyle(EonaColor.textPrimary)
            Text(label)
                .font(.xrFootnote)
                .foregroundStyle(EonaColor.textTertiary)
        }
    }

    /// "8 min", "1 h 05" — the way a driver reads a trip.
    static func duration(_ seconds: Int) -> String {
        let minutes = (seconds + 30) / 60
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    /// "820 m", "12,4 km".
    static func distance(_ meters: Int) -> String {
        if meters < 1000 { return "\(meters) m" }
        return String(format: "%.1f km", Double(meters) / 1000).replacingOccurrences(of: ".", with: ",")
    }
}

/// "Ralentissement du trafic ?": two large answers, readable at a glance; it goes by itself
/// after a few seconds.
private struct SlowdownPromptCard: View {
    let onAnswer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.md) {
            HStack(spacing: EonaSpacing.sm) {
                EonaIconView(icon: .asset(.reportTrafficJam), size: 24)
                    .foregroundStyle(EonaColor.warning)
                Text("Ralentissement du trafic ?")
                    .font(.xrHeadline)
                    .foregroundStyle(EonaColor.textPrimary)
                Spacer(minLength: 0)
            }
            HStack(spacing: EonaSpacing.sm) {
                EonaButton(title: "Non", variant: .secondary, fillWidth: true) { onAnswer(false) }
                EonaButton(title: "Oui", fillWidth: true) { onAnswer(true) }
            }
        }
        .padding(EonaSpacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: EonaRadius.lg))
    }
}

private struct RouteErrorBanner: View {
    var body: some View {
        HStack(spacing: EonaSpacing.sm) {
            Image(EonaSymbol.warning)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(EonaColor.hazard)
            Text("Itinéraire indisponible — vérifie la connexion et réessaie.")
                .font(.xrSubhead)
                .foregroundStyle(EonaColor.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(EonaSpacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: EonaRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: EonaRadius.lg).strokeBorder(EonaColor.hazard, lineWidth: 1)
        }
    }
}
