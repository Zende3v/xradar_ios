import SwiftUI
import EonaData

/// Trajets enregistrés, plus récents d'abord. Aucun auteur ni lieu dans modèle ou affichage.
struct EonaAdminTripsScreen: View {
    let services: AppServices
    let access: AdminAccessState
    @State private var trips: [AdminTrip] = []
    @State private var next: Int?
    @State private var total = 0
    @State private var retention: Int?
    @State private var loaded = false
    @State private var loading = false
    @State private var message: String?
    @State private var refreshID = UUID()
    @State private var requestID = UUID()
    @State private var pagingTask: Task<Void, Never>?

    var body: some View {
        AdminGate(services: services, access: access) {
            ScrollView {
                VStack(alignment: .leading, spacing: EonaSpacing.lg) {
                    if loaded {
                        Text("\(AdminFormat.count(total)) trajets conservés · ordre par départ")
                            .font(.xrFootnote).foregroundStyle(EonaPlusStyle.secondary)
                        if let retention {
                            Text("\(retention) derniers trajets par compte. Flux anonyme.")
                                .font(.xrFootnote).foregroundStyle(EonaPlusStyle.secondary)
                        }
                    }
                    if loading && trips.isEmpty { AdminLoading() }
                    if let message {
                        AdminNotice(title: "Chargement impossible", message: message, retry: { refreshID = UUID() })
                    } else if loaded && trips.isEmpty {
                        AdminNotice(title: "Aucun trajet", message: "Aucun trajet enregistré actuellement.")
                    }
                    if !trips.isEmpty {
                        EonaPlusGroup {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(trips) { trip in
                                    AdminTripRow(trip: trip)
                                    if trip.id != trips.last?.id { EonaPlusDivider().padding(.horizontal, EonaSpacing.lg) }
                                }
                            }
                        }
                    }
                    if next != nil {
                        Button(loading ? "Chargement…" : "Plus anciens") {
                            pagingTask?.cancel()
                            pagingTask = Task { await load(reset: false) }
                        }
                        .font(.xrBodyStrong).foregroundStyle(EonaPlusStyle.lavender)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .disabled(loading)
                    }
                }
                .padding(EonaSpacing.lg)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable { await load(reset: true) }
        }
        .adminPage("Trajets terminés")
        .task(id: refreshID) { await load(reset: true) }
        .onDisappear { pagingTask?.cancel() }
    }

    private func load(reset: Bool) async {
        guard access.permits(services), let token = services.account.token else { return }
        if !reset && loading { return }
        let id = UUID()
        requestID = id
        loading = true
        defer { if requestID == id { loading = false } }
        do {
            let page = try await AdminAPI(client: services.client).trips(offset: reset ? 0 : (next ?? 0), token: token)
            guard !Task.isCancelled, requestID == id, access.permits(services), token == services.account.token else { return }
            if reset { trips = page.trips }
            else {
                let seen = Set(trips.map(\.id))
                trips.append(contentsOf: page.trips.filter { !seen.contains($0.id) })
            }
            next = page.next
            total = page.total
            retention = page.retentionPerAccount
            loaded = true
            message = nil
        } catch {
            guard !Task.isCancelled, token == services.account.token else { return }
            let failure = await access.receive(error, services: services)
            guard requestID == id else { return }
            if let failure { message = failure }
            if !access.permits(services) { trips = []; next = nil }
        }
    }
}

private struct AdminTripRow: View {
    let trip: AdminTrip

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            Text("Départ \(Date(timeIntervalSince1970: trip.startedAt / 1000).formatted(date: .abbreviated, time: .shortened))")
                .font(.xrBodyStrong).foregroundStyle(EonaPlusStyle.primary)
            Text("\(AdminFormat.count(trip.distanceMeters)) m · \(duration)")
                .font(.xrSubhead).monospacedDigit().foregroundStyle(EonaPlusStyle.secondary)
            HStack(spacing: EonaSpacing.sm) {
                if let arrived = trip.arrived {
                    Text(arrived ? "Arrivée atteinte" : "Trajet arrêté")
                        .foregroundStyle(arrived ? EonaPlusStyle.mint : EonaPlusStyle.peach)
                } else { Text("Arrivée non renseignée").foregroundStyle(EonaPlusStyle.muted) }
                if !trip.engines.isEmpty { Text(trip.engines.joined(separator: " / ").uppercased()).foregroundStyle(EonaPlusStyle.secondary) }
            }
            .font(.xrFootnote)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(EonaSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var duration: String {
        if trip.durationSeconds < 60 { return "\(trip.durationSeconds) s" }
        let minutes = trip.durationSeconds / 60
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}
