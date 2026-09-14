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

    @Environment(\.scenePhase) private var scenePhase
    @State private var following = true
    @State private var reportOpen = false
    @State private var limitReportOpen = false
    @State private var pendingDelete: String?
    @State private var paywall = false
    @State private var dockProgress: CGFloat = 0
    @State private var heights = Heights(safe: 700, screen: 800)
    @State private var aboveDockHeight: CGFloat = 0

    var body: some View {
        let state = model.state
        let restricted = services.account.account?.isRestricted == true
        let dockOpen = dockProgress > DriveDock.openThreshold
        let onReportTap: ((String) -> Void)? = services.account.role == .admin ? { pendingDelete = $0 } : nil

        ZStack {
            DriveMapView(
                location: state.location,
                content: state.map,
                following: following,
                mapStyle: services.preferences.settings.mapStyle,
                stadiaAPIKey: services.configuration.stadiaAPIKey,
                onUserGesture: { following = false },
                onReportTap: onReportTap
            )
            .ignoresSafeArea()

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
        .alert("Abonnement requis", isPresented: $paywall) {
            Button("Compris", role: .cancel) {}
        } message: {
            Text("Ton essai gratuit est terminé. La carte reste disponible ; la navigation, les alertes et les signalements reviennent avec un abonnement membre.")
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
                            if restricted { paywall = true } else { onOpenSearch() }
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
    }

    // MARK: Bottom

    private func bottomColumn(_ state: DriveState, restricted: Bool, dockOpen: Bool) -> some View {
        // Alerts swiped away stay off the HUD for a while (still live for the voice).
        let shownAlerts = state.alerts.filter { !model.dismissedAlerts.contains($0.key) }
        let showAlerts = !shownAlerts.isEmpty && !restricted
        let hasAbove = showAlerts || state.routeError || !dockOpen
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
                progress: $dockProgress,
                // A position is needed to report a limit.
                onLimitClick: state.isSearchingGps ? nil : {
                    if restricted { paywall = true } else { limitReportOpen = true }
                }
            )
        }
        .padding(XRadarSpacing.lg)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .animation(.snappy, value: showAlerts)
        .animation(.snappy, value: state.routeError)
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
                        XRadarIconButton(icon: .symbol(.music), label: model.musicOpen ? "Fermer la musique" : "Musique", size: 56) {
                            model.toggleMusic()
                        }
                        // The main crowdsourcing action: signal something on the road.
                        XRadarIconButton(icon: .asset(.report), label: "Signaler", size: 56, tint: XRadarColor.hazard) {
                            if restricted { paywall = true } else { reportOpen = true }
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
