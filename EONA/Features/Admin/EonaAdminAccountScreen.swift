import SwiftUI
import EonaData

/// Gestion réversible. Chaque changement de droits demande confirmation dans application.
struct EonaAdminAccountScreen: View {
    let services: AppServices
    let access: AdminAccessState
    let onChange: (AdminAccount) -> Void
    @State private var account: AdminAccount
    @State private var displayName: String
    @State private var role: String
    @State private var reason = ""
    @State private var loaded = false
    @State private var loading = false
    @State private var working = false
    @State private var message: String?
    @State private var pending: AdminAccountAction?
    @State private var refreshID = UUID()
    @State private var mutationTask: Task<Void, Never>?

    init(services: AppServices, access: AdminAccessState, account: AdminAccount, onChange: @escaping (AdminAccount) -> Void = { _ in }) {
        self.services = services
        self.access = access
        self.onChange = onChange
        _account = State(initialValue: account)
        _displayName = State(initialValue: account.displayName ?? account.username ?? "")
        _role = State(initialValue: account.role)
    }

    private var isSelf: Bool { services.account.account?.id == account.id }
    private var unavailable: Bool { working || loading || !loaded || !access.permits(services) }
    private var changed: Bool { displayName != (account.displayName ?? account.username ?? "") || role != account.role }

    var body: some View {
        AdminGate(services: services, access: access) {
            ScrollView {
                VStack(alignment: .leading, spacing: EonaSpacing.xxl) {
                    VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                        Text(account.name).font(.xrTitleLarge).foregroundStyle(EonaPlusStyle.primary)
                        Text(AdminFormat.access(account)).font(.xrSubhead).foregroundStyle(account.banned || account.suspended == true ? EonaPlusStyle.peach : EonaPlusStyle.mint)
                    }
                    if loading { AdminLoading() }
                    if let message {
                        AdminNotice(title: "Compte", message: message, retry: { refreshID = UUID() })
                    }
                    AdminSection(title: "Identité") {
                        AdminValueRow(title: "Pseudo", value: account.username ?? "—")
                        AdminValueRow(title: "Email", value: account.email ?? "—")
                        EonaPlusDivider().padding(.horizontal, EonaSpacing.lg)
                        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                            Text("Nom affiché").font(.xrFootnote).foregroundStyle(EonaPlusStyle.secondary)
                            TextField("Nom affiché", text: $displayName).font(.xrBody)
                                .textInputAutocapitalization(.words).autocorrectionDisabled()
                        }
                        .padding(EonaSpacing.lg)
                        .disabled(unavailable)
                        Picker("Rôle", selection: $role) {
                            Text("Invité").tag("guest")
                            Text("Client").tag("client")
                            Text("Admin").tag("admin")
                        }
                        .padding(EonaSpacing.lg)
                        .disabled(unavailable || isSelf)
                        Button { pending = .save } label: {
                            Text(working ? "Enregistrement…" : "Enregistrer")
                                .font(.xrBodyStrong).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .padding(.horizontal, EonaSpacing.lg).padding(.bottom, EonaSpacing.sm)
                        .disabled(unavailable || !changed)
                    }
                    AdminSection(title: "Activité") {
                        AdminValueRow(title: "État observé", value: account.inTrip == true ? "En trajet" : account.online == true ? "Connecté" : "Hors ligne")
                        AdminValueRow(title: "Création", value: AdminFormat.date(account.createdAt))
                        AdminValueRow(title: "Dernière connexion", value: AdminFormat.date(account.lastSeenAt))
                        AdminValueRow(title: "Trajets enregistrés", value: AdminFormat.count(account.stats?.tripCount))
                    }
                    AdminSection(title: "Application & appareils") {
                        AdminValueRow(title: "Plateforme", value: account.platform?.uppercased() ?? "—")
                        AdminValueRow(title: "Modèle", value: account.app?.model ?? "—")
                        AdminValueRow(title: "Système", value: account.app?.osVersion ?? "—")
                        AdminValueRow(title: "Version EONA", value: account.app?.appVersion ?? "—")
                        AdminValueRow(title: "Appareils connus", value: AdminFormat.count(account.devices.count))
                        if !account.devices.isEmpty {
                            DisclosureGroup("Identifiants appareil") {
                                ForEach(account.devices, id: \.self) { device in
                                    Text(device).font(.system(.footnote, design: .monospaced))
                                        .foregroundStyle(EonaPlusStyle.secondary).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, EonaSpacing.xs)
                                }
                            }
                            .font(.xrSubhead).padding(EonaSpacing.lg)
                        }
                    }
                    AdminSection(title: "Accès") {
                        if account.banned {
                            AdminValueRow(title: "Banni depuis", value: AdminFormat.date(account.bannedAt))
                            if let reason = account.banReason, !reason.isEmpty { AdminValueRow(title: "Motif bannissement", value: reason) }
                        }
                        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                            Text("Motif facultatif").font(.xrFootnote).foregroundStyle(EonaPlusStyle.secondary)
                            TextField("Motif", text: $reason, axis: .vertical).lineLimit(1...3)
                        }
                        .padding(EonaSpacing.lg).disabled(unavailable)
                        EonaPlusDivider().padding(.horizontal, EonaSpacing.lg)
                        actionButton(account.banned ? .unban : .ban)
                        EonaPlusDivider().padding(.horizontal, EonaSpacing.lg)
                        actionButton(account.suspended == true || account.revoked == true ? .restore : .suspend)
                        EonaPlusDivider().padding(.horizontal, EonaSpacing.lg)
                        actionButton(.revokeSessions)
                    }
                    if isSelf {
                        Text("Gestion de tes propres droits désactivée ici.")
                            .font(.xrFootnote).foregroundStyle(EonaPlusStyle.secondary).padding(.horizontal, EonaSpacing.lg)
                    }
                }
                .padding(EonaSpacing.lg)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable { await load() }
        }
        .adminPage("Compte")
        .task(id: refreshID) { await load() }
        .onDisappear { mutationTask?.cancel() }
        .onChange(of: access.denied) { _, denied in
            if denied != nil { pending = nil; mutationTask?.cancel() }
        }
        .alert(pending?.confirmation ?? "Confirmer", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { action in
            Button("Annuler", role: .cancel) { pending = nil }
            Button(action.title, role: action.destructive ? .destructive : nil) {
                pending = nil
                mutationTask?.cancel()
                mutationTask = Task { await perform(action) }
            }
        } message: { action in
            Text(action == .save ? "Nom affiché : \(displayName). Rôle : \(AdminFormat.role(role))." : action.explanation)
        }
    }

    private func actionButton(_ action: AdminAccountAction) -> some View {
        Button { pending = action } label: {
            HStack(spacing: EonaSpacing.md) {
                Image(systemName: action.symbol).frame(width: 22)
                Text(action.title).font(.xrBodyStrong)
                Spacer(minLength: EonaSpacing.sm)
                if working { ProgressView().tint(EonaPlusStyle.lavender) }
            }
            .foregroundStyle(action.destructive ? EonaPlusStyle.peach : EonaPlusStyle.lavender)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(EonaSpacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(unavailable || isSelf)
    }

    private func load() async {
        guard !loading, !working, access.permits(services), let token = services.account.token else { return }
        loading = true
        defer { loading = false }
        do {
            let fresh = try await AdminAPI(client: services.client).account(id: account.id, token: token)
            guard !Task.isCancelled, access.permits(services), token == services.account.token else { return }
            let preserveDraft = changed && loaded
            account = fresh
            if !preserveDraft { displayName = fresh.displayName ?? fresh.username ?? ""; role = fresh.role }
            loaded = true
            message = nil
            onChange(fresh)
        } catch {
            guard !Task.isCancelled, token == services.account.token else { return }
            if let failure = await access.receive(error, services: services) { message = failure }
        }
    }

    private func perform(_ action: AdminAccountAction) async {
        guard !unavailable, access.permits(services), let token = services.account.token else { return }
        working = true
        message = nil
        defer { working = false }
        do {
            let api = AdminAPI(client: services.client)
            let fresh: AdminAccount
            if action == .save {
                fresh = try await api.update(id: account.id, role: role, displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines), token: token)
            } else {
                let source = action == .unban ? (account.banId ?? account.id) : account.id
                let result = try await api.action(id: source, action: action.rawValue, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines), token: token)
                if action == .unban || result.account?.id != account.id {
                    fresh = try await api.account(id: account.id, token: token)
                } else if let updated = result.account {
                    fresh = updated
                } else { throw AdminAPIError.invalidResponse }
            }
            guard !Task.isCancelled, access.permits(services), token == services.account.token else { return }
            account = fresh
            displayName = fresh.displayName ?? fresh.username ?? ""
            role = fresh.role
            reason = ""
            onChange(fresh)
            if isSelf { await services.account.reload() }
        } catch {
            guard !Task.isCancelled, token == services.account.token else { return }
            if let failure = await access.receive(error, services: services) { message = failure }
        }
    }
}

private enum AdminAccountAction: String {
    case ban, unban, suspend, restore, revokeSessions, save
    var destructive: Bool { self == .ban || self == .suspend || self == .revokeSessions }
    var title: String {
        switch self {
        case .ban: "Bannir compte, email et appareils"
        case .unban: "Retirer bannissement"
        case .suspend: "Suspendre compte"
        case .restore: "Réactiver compte"
        case .revokeSessions: "Fermer toutes sessions"
        case .save: "Enregistrer"
        }
    }
    var confirmation: String {
        switch self {
        case .ban: "Bannir ce compte ?"
        case .unban: "Retirer bannissement ?"
        case .suspend: "Suspendre ce compte ?"
        case .restore: "Réactiver ce compte ?"
        case .revokeSessions: "Fermer toutes sessions ?"
        case .save: "Modifier ce compte ?"
        }
    }
    var explanation: String {
        switch self {
        case .ban: "Compte, email et appareils connus bloqués. Toutes sessions fermées. Compte conservé."
        case .unban: "Bannissement du compte, email et appareils retiré. Suspension séparée conservée."
        case .suspend: "Accès application suspendu. Sessions fermées. Compte et historique conservés."
        case .restore: "Suspension retirée. Bannissement éventuel reste applicable."
        case .revokeSessions: "Toutes sessions actives fermées. Droits et historique du compte conservés."
        case .save: "Modification du nom affiché et du rôle."
        }
    }
    var symbol: String {
        switch self {
        case .ban: "hand.raised.fill"
        case .unban: "hand.raised.slash.fill"
        case .suspend: "pause.circle.fill"
        case .restore: "play.circle.fill"
        case .revokeSessions: "rectangle.portrait.and.arrow.right"
        case .save: "checkmark"
        }
    }
}

struct EonaAdminCreateAccountSheet: View {
    let services: AppServices
    let access: AdminAccessState
    let onCreated: () -> Void
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var role = "client"
    @State private var working = false
    @State private var message: String?
    @State private var confirming = false
    @State private var mutationTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    private var ready: Bool {
        !working && access.permits(services) && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            AdminGate(services: services, access: access) {
                ScrollView {
                    VStack(alignment: .leading, spacing: EonaSpacing.xxl) {
                        AdminSection(title: "Nouveau compte") {
                            TextField("Pseudo", text: $username).textContentType(.username)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().padding(EonaSpacing.lg)
                            EonaPlusDivider().padding(.horizontal, EonaSpacing.lg)
                            TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().padding(EonaSpacing.lg)
                            EonaPlusDivider().padding(.horizontal, EonaSpacing.lg)
                            SecureField("Mot de passe", text: $password).textContentType(.newPassword).padding(EonaSpacing.lg)
                            EonaPlusDivider().padding(.horizontal, EonaSpacing.lg)
                            Picker("Rôle", selection: $role) {
                                Text("Invité").tag("guest")
                                Text("Client").tag("client")
                                Text("Admin").tag("admin")
                            }.padding(EonaSpacing.lg)
                        }
                        .disabled(working)
                        if let message { AdminNotice(title: "Création impossible", message: message) }
                        Button(working ? "Création…" : "Créer compte") { confirming = true }
                            .font(.xrBodyStrong).frame(minHeight: 44).disabled(!ready)
                    }
                    .padding(EonaSpacing.lg)
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .adminPage("Créer un compte")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() }.disabled(working) }
            }
        }
        .presentationBackground(EonaPlusStyle.canvas)
        .onDisappear { mutationTask?.cancel(); password = "" }
        .alert("Créer ce compte ?", isPresented: $confirming) {
            Button("Annuler", role: .cancel) {}
            Button("Créer") { mutationTask = Task { await create() } }
        } message: {
            Text("\(username) · \(email) · \(AdminFormat.role(role)).")
        }
    }

    private func create() async {
        guard ready, let token = services.account.token else { return }
        working = true
        defer { working = false }
        do {
            _ = try await AdminAPI(client: services.client).create(username: username.trimmingCharacters(in: .whitespacesAndNewlines), email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password, role: role, token: token)
            guard !Task.isCancelled, access.permits(services), token == services.account.token else { return }
            password = ""
            onCreated()
            dismiss()
        } catch {
            guard !Task.isCancelled, token == services.account.token else { return }
            if let failure = await access.receive(error, services: services) { message = failure }
        }
    }
}
