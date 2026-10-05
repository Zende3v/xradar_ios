import SwiftUI
import EonaData

/// Recherche paginée, statut observé et accès à gestion individuelle.
struct EonaAdminAccountsScreen: View {
    let services: AppServices
    let access: AdminAccessState
    @State private var query = ""
    @State private var role = ""
    @State private var bannedOnly = false
    @State private var accounts: [AdminAccount] = []
    @State private var next: Int?
    @State private var total = 0
    @State private var loaded = false
    @State private var loading = false
    @State private var message: String?
    @State private var creating = false
    @State private var refreshID = UUID()
    @State private var requestID = UUID()
    @State private var pagingTask: Task<Void, Never>?

    private var filter: AdminAccountFilter { AdminAccountFilter(query: query, role: role, bannedOnly: bannedOnly, refreshID: refreshID) }

    var body: some View {
        AdminGate(services: services, access: access) {
            ScrollView {
                VStack(alignment: .leading, spacing: EonaSpacing.lg) {
                    HStack(spacing: EonaSpacing.sm) {
                        Image(systemName: "magnifyingglass").foregroundStyle(EonaPlusStyle.muted)
                        TextField("Pseudo, email, compte", text: $query)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.search)
                    }
                    .padding(EonaSpacing.lg)
                    .background(EonaPlusStyle.surface, in: .capsule)
                    HStack(alignment: .center, spacing: EonaSpacing.lg) {
                        Picker("Rôle", selection: $role) {
                            Text("Tous rôles").tag("")
                            Text("Invités").tag("guest")
                            Text("Clients").tag("client")
                            Text("Admins").tag("admin")
                        }.pickerStyle(.menu)
                        Toggle("Bannis", isOn: $bannedOnly).toggleStyle(.button)
                    }
                    .font(.xrSubhead)
                    EonaPlusGroup {
                        NavigationLink {
                            EonaAdminBansScreen(services: services, access: access)
                        } label: {
                            AdminNavigationRow(title: "Bannissements", subtitle: "Compte, email et appareils connus", symbol: "hand.raised.fill", color: EonaPlusStyle.peach)
                        }.buttonStyle(.plain)
                    }
                    if loaded { EonaPlusLabel("\(AdminFormat.count(total)) comptes") }
                    if loading && accounts.isEmpty { AdminLoading() }
                    if let message {
                        AdminNotice(title: "Chargement impossible", message: message, retry: { refreshID = UUID() })
                    } else if loaded && accounts.isEmpty {
                        AdminNotice(title: "Aucun compte", message: "Aucun compte ne correspond à recherche.")
                    }
                    if !accounts.isEmpty {
                        EonaPlusGroup {
                            LazyVStack(spacing: 0) {
                                ForEach(accounts) { account in
                                    NavigationLink {
                                        EonaAdminAccountScreen(services: services, access: access, account: account) { updated in
                                            accounts = accounts.map { $0.id == updated.id ? updated : $0 }
                                        }
                                    } label: {
                                        AdminNavigationRow(title: account.name, subtitle: accountSubtitle(account), symbol: account.role == "admin" ? "checkmark.shield.fill" : "person.fill", color: account.banned || account.suspended == true ? EonaPlusStyle.peach : EonaPlusStyle.lavender)
                                    }.buttonStyle(.plain)
                                    if account.id != accounts.last?.id { EonaPlusDivider().padding(.leading, 68) }
                                }
                            }
                        }
                    }
                    if next != nil {
                        Button(loading ? "Chargement…" : "Plus de comptes") {
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
        .adminPage("Comptes")
        .toolbar {
            if access.permits(services) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Créer un compte")
                }
            }
        }
        .task(id: filter) {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await load(reset: true)
        }
        .onDisappear { pagingTask?.cancel() }
        .sheet(isPresented: $creating) {
            EonaAdminCreateAccountSheet(services: services, access: access) {
                creating = false
                refreshID = UUID()
            }
        }
    }

    private func accountSubtitle(_ account: AdminAccount) -> String {
        let activity = account.inTrip == true ? "En trajet" : account.online == true ? "Connecté" : "Hors ligne"
        return "\(AdminFormat.access(account)) · \(activity)"
    }

    private func load(reset: Bool) async {
        guard access.permits(services), let token = services.account.token else { return }
        if !reset && loading { return }
        let id = UUID()
        requestID = id
        loading = true
        let requestedFilter = filter
        defer { if requestID == id { loading = false } }
        do {
            let page = try await AdminAPI(client: services.client).accounts(query: query.trimmingCharacters(in: .whitespacesAndNewlines), role: role.isEmpty ? nil : role, banned: bannedOnly ? true : nil, offset: reset ? 0 : (next ?? 0), token: token)
            guard !Task.isCancelled, requestID == id, filter == requestedFilter, access.permits(services), token == services.account.token else { return }
            if reset { accounts = page.accounts }
            else {
                let seen = Set(accounts.map(\.id))
                accounts.append(contentsOf: page.accounts.filter { !seen.contains($0.id) })
            }
            total = page.total
            next = page.next
            loaded = true
            message = nil
        } catch {
            guard !Task.isCancelled, token == services.account.token else { return }
            let failure = await access.receive(error, services: services)
            guard requestID == id else { return }
            if let failure { message = failure }
            if !access.permits(services) { accounts = []; next = nil; creating = false }
        }
    }
}

private struct AdminAccountFilter: Equatable {
    let query: String
    let role: String
    let bannedOnly: Bool
    let refreshID: UUID
}
