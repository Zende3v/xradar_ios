import SwiftUI
import EonaData

/// Présence observée et mesures réelles. Rafraîchissement uniquement pendant affichage actif.
struct EonaAdminScreen: View {
    let services: AppServices
    @State private var access = AdminAccessState()
    @State private var overview: AdminOverview?
    @State private var loading = false
    @State private var message: String?
    @State private var visible = false
    @State private var manualTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    private var polling: Bool { visible && scenePhase == .active && access.permits(services) }

    var body: some View {
        AdminGate(services: services, access: access) {
            ScrollView {
                VStack(alignment: .leading, spacing: EonaSpacing.xxl) {
                    if let overview { content(overview) }
                    else if loading { AdminLoading() }
                    else { AdminNotice(title: "Pilotage EONA", message: message ?? "Aucune mesure disponible.", retry: retry) }
                    if let message, overview != nil {
                        AdminNotice(title: "Actualisation impossible", message: message, retry: retry)
                    }
                }
                .padding(EonaSpacing.lg)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable { await load() }
        }
        .adminPage("Pilotage EONA")
        .onAppear { visible = true }
        .onDisappear { visible = false; manualTask?.cancel() }
        .task(id: polling) {
            guard polling else { return }
            while !Task.isCancelled && access.permits(services) {
                await load()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    @ViewBuilder
    private func content(_ data: AdminOverview) -> some View {
        Text("Actualisé \(AdminFormat.date(data.generatedAt))")
            .font(.xrFootnote).foregroundStyle(EonaPlusStyle.secondary)
        AdminSection(title: "Présence") {
            ForEach(data.presence.groups) { group in
                PresenceGroupRow(group: group)
                if group.id != data.presence.groups.last?.id { EonaPlusDivider().padding(.horizontal, EonaSpacing.lg) }
            }
        }
        Text("Présence observée sur \(data.presence.ttlSeconds) s. Sans signal récent, compte classé hors ligne.")
            .font(.xrFootnote).foregroundStyle(EonaPlusStyle.secondary).padding(.horizontal, EonaSpacing.lg)
        AdminSection(title: "Activité") {
            NavigationLink {
                EonaAdminTripsScreen(services: services, access: access)
            } label: {
                AdminNavigationRow(title: "Trajets terminés", subtitle: "\(AdminFormat.count(data.trips.totalRecorded)) enregistrés · \(AdminFormat.count(data.trips.retainedCount)) conservés", symbol: "arrow.triangle.turn.up.right.diamond.fill", color: EonaPlusStyle.sky)
            }.buttonStyle(.plain)
            EonaPlusDivider().padding(.leading, 68)
            NavigationLink {
                EonaAdminAccountsScreen(services: services, access: access)
            } label: {
                AdminNavigationRow(title: "Comptes", subtitle: "\(AdminFormat.count(data.accounts.total)) comptes · \(data.accounts.banned) bannis · \(data.accounts.suspended) suspendus", symbol: "person.2.fill", color: EonaPlusStyle.mint)
            }.buttonStyle(.plain)
        }
        AdminSection(title: "Valhalla") {
            AdminValueRow(title: "État", value: engineState(data.routing.valhalla.state), color: data.routing.valhalla.state == "up" ? EonaPlusStyle.mint : EonaPlusStyle.peach)
            EonaPlusDivider().padding(.horizontal, EonaSpacing.lg)
            AdminValueRow(title: "Moteur servi", value: data.routing.provider?.uppercased() ?? "—")
            AdminValueRow(title: "Version", value: data.routing.valhalla.version ?? "—")
            AdminValueRow(title: "Carte", value: data.routing.valhalla.mapVersion ?? "—")
            AdminValueRow(title: "Réponses Valhalla", value: AdminFormat.count(data.routingStats.totalRequests))
            AdminValueRow(title: "Réponses cette semaine", value: AdminFormat.count(data.routingStats.weekRequests))
            AdminValueRow(title: "Secours ORS", value: AdminFormat.count(data.routing.fallbacks?.total))
            AdminValueRow(title: "Depuis", value: AdminFormat.date(data.routing.fallbacks?.since))
            AdminValueRow(title: "Réponses cache", value: AdminFormat.count(data.routingStats.cacheHits))
            AdminValueRow(title: "Latence médiane API", value: AdminFormat.milliseconds(data.routingStats.medianMs))
            AdminValueRow(title: "Latence p95 API", value: AdminFormat.milliseconds(data.routingStats.p95Ms))
        }
        VStack(alignment: .leading, spacing: EonaSpacing.xs) {
            Text(data.routingStats.available ? "Journal conservé \(data.routingStats.retentionDays) jours. Latence API, cache inclus." : "Mesures de routage indisponibles.")
            Text("Échecs moteur non attribués dans journal.")
            Text("Secours ORS comptés depuis démarrage du backend.")
        }
        .font(.xrFootnote).foregroundStyle(EonaPlusStyle.secondary).padding(.horizontal, EonaSpacing.lg)
        AdminSection(title: "HERE · consommation") {
            AdminValueRow(title: "Appels ce mois", value: AdminFormat.count(data.here.monthUsed))
            AdminValueRow(title: "Estimation ce mois", value: AdminFormat.euros(data.here.estimatedMonthEUR), color: EonaPlusStyle.peach)
            AdminValueRow(title: "Budget mensuel estimé", value: AdminFormat.euros(data.here.monthlyBudgetEUR))
            AdminValueRow(title: "Plafond journalier", value: data.here.dailyCap.map { AdminFormat.count($0) } ?? "Aucun")
            EonaPlusDivider().padding(.horizontal, EonaSpacing.lg)
            AdminValueRow(title: "Appels cette semaine", value: AdminFormat.count(data.here.history.weekRequests))
            AdminValueRow(title: "Estimation semaine", value: AdminFormat.euros(data.here.history.weekEstimatedEUR))
            AdminValueRow(title: "Appels cumulés", value: AdminFormat.count(data.here.history.totalRequests))
            AdminValueRow(title: "Estimation cumulée", value: AdminFormat.euros(data.here.history.totalEstimatedEUR))
            if let blocked = data.here.blocked { AdminValueRow(title: "Restriction", value: hereReason(blocked), color: EonaPlusStyle.peach) }
        }
        VStack(alignment: .leading, spacing: EonaSpacing.xs) {
            Text("Coûts estimés selon tarifs configurés.")
            Text("Historique depuis \(AdminFormat.date(data.here.history.since)).")
            if !data.here.history.earlierHistoryComplete { Text("Cumul partiel : historique antérieur incomplet.") }
            if !data.here.history.weekComplete { Text("Semaine partielle depuis démarrage de collecte.") }
        }
        .font(.xrFootnote).foregroundStyle(EonaPlusStyle.secondary).padding(.horizontal, EonaSpacing.lg)
    }

    private func load() async {
        guard polling, !loading, let token = services.account.token else { return }
        loading = true
        defer { loading = false }
        do {
            let fresh = try await AdminAPI(client: services.client).overview(token: token)
            guard !Task.isCancelled, polling, access.permits(services), token == services.account.token else { return }
            overview = fresh
            message = nil
        } catch {
            guard !Task.isCancelled, token == services.account.token else { return }
            if let failure = await access.receive(error, services: services) { message = failure }
            if !access.permits(services) { overview = nil }
        }
    }

    private func retry() {
        manualTask?.cancel()
        manualTask = Task { await load() }
    }

    private func engineState(_ state: String) -> String {
        switch state { case "up": "Opérationnel"; case "down": "Indisponible"; case "disabled": "Désactivé"; default: "À mesurer" }
    }

    private func hereReason(_ reason: String) -> String {
        switch reason {
        case "monthly budget": "Budget mensuel atteint"
        case "daily cap": "Plafond journalier atteint"
        case "storage unavailable": "Compteurs indisponibles"
        case "key missing": "Service non configuré"
        default: "Appels suspendus"
        }
    }
}

private struct PresenceGroupRow: View {
    let group: AdminPresenceGroup
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var color: Color { group.id == "admin" ? EonaPlusStyle.mint : group.id == "client" ? EonaPlusStyle.lavender : EonaPlusStyle.sky }

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.md) {
            HStack(spacing: EonaSpacing.sm) {
                Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
                Text(group.label).font(.xrBodyStrong).foregroundStyle(EonaPlusStyle.primary)
                Text("\(AdminFormat.count(group.total)) comptes").font(.xrFootnote).foregroundStyle(EonaPlusStyle.secondary)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: EonaSpacing.sm) { values }
            } else {
                HStack(alignment: .top, spacing: EonaSpacing.sm) { values }
            }
        }
        .padding(EonaSpacing.lg)
    }

    @ViewBuilder private var values: some View {
        cell("Connectés", group.online)
        cell("Hors ligne", group.offline)
        cell("En trajet", group.inTrip)
    }

    private func cell(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: EonaSpacing.xs) {
            Text(AdminFormat.count(value)).font(.xrHeadline).monospacedDigit().foregroundStyle(color)
            Text(label).font(.xrFootnote).foregroundStyle(EonaPlusStyle.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
