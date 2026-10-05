import SwiftUI
import EonaData

/// Registre durable : bannissement reste visible après suppression du compte source.
struct EonaAdminBansScreen: View {
    let services: AppServices
    let access: AdminAccessState
    @State private var bans: [AdminBanRecord] = []
    @State private var total = 0
    @State private var loaded = false
    @State private var loading = false
    @State private var workingID: String?
    @State private var message: String?
    @State private var pending: AdminBanRecord?
    @State private var refreshID = UUID()
    @State private var mutationTask: Task<Void, Never>?

    var body: some View {
        AdminGate(services: services, access: access) {
            ScrollView {
                VStack(alignment: .leading, spacing: EonaSpacing.lg) {
                    if loaded { EonaPlusLabel("\(AdminFormat.count(total)) bannissements") }
                    if loading && bans.isEmpty { AdminLoading() }
                    if let message { AdminNotice(title: "Bannissements", message: message, retry: { refreshID = UUID() }) }
                    else if loaded && bans.isEmpty { AdminNotice(title: "Aucun bannissement", message: "Registre vide.") }
                    ForEach(bans) { record in
                        EonaPlusGroup {
                            VStack(alignment: .leading, spacing: EonaSpacing.md) {
                                Text(record.displayName ?? (record.accountExists ? "Compte" : "Compte supprimé"))
                                    .font(.xrBodyStrong).foregroundStyle(EonaPlusStyle.primary)
                                if let email = record.email { Text(email).font(.xrSubhead).foregroundStyle(EonaPlusStyle.secondary) }
                                Text(AdminFormat.date(record.bannedAt)).font(.xrFootnote).foregroundStyle(EonaPlusStyle.secondary)
                                if let reason = record.reason, !reason.isEmpty {
                                    Text(reason).font(.xrSubhead).foregroundStyle(EonaPlusStyle.secondary)
                                }
                                Text("\(record.deviceCount) appareils connus · \(record.accountExists ? "Compte conservé" : "Compte source supprimé")")
                                    .font(.xrFootnote).foregroundStyle(EonaPlusStyle.secondary)
                                Button {
                                    pending = record
                                } label: {
                                    HStack(spacing: EonaSpacing.sm) {
                                        if workingID == record.id { ProgressView().tint(EonaPlusStyle.lavender) }
                                        Text("Retirer bannissement").font(.xrBodyStrong)
                                    }.frame(minHeight: 44, alignment: .leading)
                                }
                                .disabled(loading || workingID != nil || record.accountId == services.account.account?.id)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(EonaSpacing.lg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(EonaSpacing.lg)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable { if workingID == nil { await load() } }
        }
        .adminPage("Bannissements")
        .task(id: refreshID) { await load() }
        .onDisappear { mutationTask?.cancel() }
        .onChange(of: access.denied) { _, denied in
            if denied != nil { pending = nil; mutationTask?.cancel() }
        }
        .alert("Retirer bannissement ?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { record in
            Button("Annuler", role: .cancel) { pending = nil }
            Button("Retirer") {
                pending = nil
                mutationTask = Task { await unban(record) }
            }
        } message: { _ in
            Text("Bannissement du compte, email et appareils connus retiré. Suspension séparée conservée.")
        }
    }

    private func load() async {
        guard !loading, access.permits(services), let token = services.account.token else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await AdminAPI(client: services.client).bans(token: token)
            guard !Task.isCancelled, access.permits(services), token == services.account.token else { return }
            bans = page.bans
            total = page.total
            loaded = true
            message = nil
        } catch {
            guard !Task.isCancelled, token == services.account.token else { return }
            if let failure = await access.receive(error, services: services) { message = failure }
            if !access.permits(services) { bans = [] }
        }
    }

    private func unban(_ record: AdminBanRecord) async {
        guard workingID == nil, access.permits(services), let token = services.account.token else { return }
        workingID = record.id
        defer { workingID = nil }
        do {
            _ = try await AdminAPI(client: services.client).action(id: record.accountId, action: "unban", token: token)
            guard !Task.isCancelled, access.permits(services), token == services.account.token else { return }
            await load()
        } catch {
            guard !Task.isCancelled, token == services.account.token else { return }
            if let failure = await access.receive(error, services: services) { message = failure }
            if !access.permits(services) { bans = [] }
        }
    }
}
