import SwiftUI
import XRadarCore
import XRadarData

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
                dark: mapDark,
                onUserGesture: { following = false },
                onReportTap: onReportTap
            )
            .ignoresSafeArea()

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
        VStack(spacing: XRadarSpacing.sm) {
            HStack(spacing: XRadarSpacing.sm) {
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
                    XRadarIconButton(icon: .symbol(.close), label: "Arrêter la navigation", size: 48) {
                        services.activeTrip.clear()
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                XRadarIconButton(icon: .symbol(.menu), label: "Menu", size: 48, action: onOpenMenu)
            }

            // Under the search bar (or the guidance), in the flow: it never covers either.
            if let notice = model.fasterNotice {
                FasterRouteBanner(notice: notice)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if model.musicOpen {
                MusicBanner(player: services.music)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, XRadarSpacing.lg)
        .padding(.vertical, XRadarSpacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.25), value: state.guidance == nil)
        .animation(.easeInOut(duration: 0.25), value: state.trip == nil)
        .animation(.snappy, value: model.musicOpen)
        .animation(.snappy, value: model.fasterNotice)
    }

    // MARK: Bottom

    private func bottomColumn(_ state: DriveState, restricted: Bool, dockOpen: Bool) -> some View {
        // Alerts swiped away stay off the HUD for a while (still live for the voice).
        let shownAlerts = state.alerts.filter { !model.dismissedAlerts.contains($0.key) }
        let showAlerts = !shownAlerts.isEmpty && !restricted
        let hasAbove = showAlerts || state.routeError || model.slowdownPrompt != nil || !dockOpen
        let expanded = min(
            heights.screen * 0.8,
            heights.safe - 2 * XRadarSpacing.lg - aboveDockHeight - (hasAbove ? XRadarSpacing.md : 0)
        )
        return VStack(spacing: 0) {
            VStack(spacing: XRadarSpacing.md) {
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
                // Alert sound and voice, reachable without opening the dock, on the left so the
                // report button stays on the right.
                if !dockOpen {
                    HStack(spacing: XRadarSpacing.sm) {
                        alertSoundButton
                        voiceButton
                        Spacer(minLength: 0)
                    }
                    .transition(.opacity)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { aboveDockHeight = $0 }

            if hasAbove {
                Color.clear.frame(height: XRadarSpacing.md)
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
        .padding(XRadarSpacing.lg)
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

    /// Alert sound: off, on, on with vibration. One button, three states.
    private var alertSoundButton: some View {
        let prefs = services.preferences.alerts
        let icon: XRadarSymbol = !prefs.sound ? .bellOff : (prefs.vibration ? .bellRinging : .bell)
        return XRadarIconButton(icon: .symbol(icon), label: "Son des alertes", size: 48) {
            services.preferences.updateAlerts { alerts in
                if !alerts.sound {
                    alerts.sound = true
                    alerts.vibration = false
                } else if !alerts.vibration {
                    alerts.vibration = true
                } else {
                    alerts.sound = false
                    alerts.vibration = false
                }
            }
        }
    }

    /// Spoken guidance and alert announcements, on or off.
    private var voiceButton: some View {
        let voice = services.preferences.alerts.voice
        return XRadarIconButton(icon: .symbol(voice ? .volumeOn : .volumeOff), label: "Annonces vocales", size: 48) {
            services.preferences.updateAlerts { $0.voice.toggle() }
        }
    }

    // MARK: Map controls

    /// Recenter, music and report share one size; they step aside while the dock is pulled up.
    private func mapControls(restricted: Bool, dockOpen: Bool) -> some View {
        ZStack {
            if !dockOpen {
                GlassEffectContainer(spacing: XRadarSpacing.sm) {
                    VStack(spacing: XRadarSpacing.sm) {
                        if !following {
                            XRadarIconButton(icon: .symbol(.recenter), label: "Recentrer", size: 56, tint: XRadarColor.accent) {
                                following = true
                            }
                        }
                        // The music shortcut is for members; an open banner can always be closed.
                        XRadarIconButton(icon: .symbol(.music), label: model.musicOpen ? "Fermer la musique" : "Musique", size: 56) {
                            if model.musicOpen || (!restricted && services.account.role != .guest) {
                                model.toggleMusic()
                            } else {
                                onBlocked(restricted ? .restricted : .music)
                            }
                        }
                        // The main crowdsourcing action: signal something on the road.
                        // Neutral glass and a grey warning triangle, as drawn in the new asset.
                        XRadarIconButton(icon: .symbol(.warning), label: "Signaler", size: 56, tint: XRadarColor.textSecondary) {
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
        .padding(.trailing, XRadarSpacing.lg)
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
            HStack(spacing: XRadarSpacing.sm) {
                Image(XRadarSymbol.search)
                    .font(.system(size: 17, weight: .semibold))
                Text("Où allez-vous ?")
                    .font(.xrBody)
                Spacer(minLength: 0)
            }
            .foregroundStyle(XRadarColor.textSecondary)
            .padding(.horizontal, XRadarSpacing.lg)
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
                Image(XRadarSymbol.appleLogo)
                Text("Plans · Mentions légales")
            }
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(XRadarColor.textSecondary.opacity(0.6))
        }
        .accessibilityLabel("Plans, mentions légales")
        .padding(.leading, XRadarSpacing.xl)
        .padding(.bottom, XRadarSpacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .ignoresSafeArea(edges: .bottom)
    }
}

/// A faster way around the traffic was taken: the time it saves, for a few seconds; or the way
/// around a closed road.
private struct FasterRouteBanner: View {
    let notice: FasterRouteNotice

    var body: some View {
        HStack(spacing: XRadarSpacing.sm) {
            Image(XRadarSymbol.fasterRoute)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(XRadarColor.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.closedRoad ? "Route fermée devant" : "Itinéraire plus rapide")
                    .font(.xrLabel)
                    .foregroundStyle(XRadarColor.textPrimary)
                Text(subtitle)
                    .font(.xrFootnote)
                    .foregroundStyle(XRadarColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(XRadarSpacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: XRadarRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: XRadarRadius.lg).strokeBorder(XRadarColor.success, lineWidth: 1)
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
        VStack(alignment: .leading, spacing: XRadarSpacing.md) {
            HStack(spacing: XRadarSpacing.md) {
                Image(XRadarSymbol.check)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(XRadarColor.success)
                    .frame(width: 48, height: 48)
                    .background(XRadarColor.success.opacity(0.18), in: .circle)
                    .scaleEffect(landed ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vous êtes arrivé")
                        .font(.xrHeadline)
                        .foregroundStyle(XRadarColor.textPrimary)
                    Text(arrival.toLabel)
                        .font(.xrFootnote)
                        .foregroundStyle(XRadarColor.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: XRadarSpacing.lg) {
                figure("Durée", Self.duration(arrival.durationSeconds))
                figure("Distance", Self.distance(arrival.distanceMeters))
                if arrival.alertsCount > 0 {
                    figure("Alertes", "\(arrival.alertsCount)")
                }
                Spacer(minLength: 0)
            }
            XRadarButton(title: "Terminé", variant: .secondary, fillWidth: true) { onDismiss() }
        }
        .padding(XRadarSpacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: XRadarRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: XRadarRadius.lg).strokeBorder(XRadarColor.success, lineWidth: 1)
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
                .foregroundStyle(XRadarColor.textPrimary)
            Text(label)
                .font(.xrFootnote)
                .foregroundStyle(XRadarColor.textTertiary)
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
        VStack(alignment: .leading, spacing: XRadarSpacing.md) {
            HStack(spacing: XRadarSpacing.sm) {
                XRadarIconView(icon: .asset(.reportTrafficJam), size: 24)
                    .foregroundStyle(XRadarColor.warning)
                Text("Ralentissement du trafic ?")
                    .font(.xrHeadline)
                    .foregroundStyle(XRadarColor.textPrimary)
                Spacer(minLength: 0)
            }
            HStack(spacing: XRadarSpacing.sm) {
                XRadarButton(title: "Non", variant: .secondary, fillWidth: true) { onAnswer(false) }
                XRadarButton(title: "Oui", fillWidth: true) { onAnswer(true) }
            }
        }
        .padding(XRadarSpacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: XRadarRadius.lg))
    }
}

private struct RouteErrorBanner: View {
    var body: some View {
        HStack(spacing: XRadarSpacing.sm) {
            Image(XRadarSymbol.warning)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(XRadarColor.hazard)
            Text("Itinéraire indisponible — vérifie la connexion et réessaie.")
                .font(.xrSubhead)
                .foregroundStyle(XRadarColor.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(XRadarSpacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: XRadarRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: XRadarRadius.lg).strokeBorder(XRadarColor.hazard, lineWidth: 1)
        }
    }
}
