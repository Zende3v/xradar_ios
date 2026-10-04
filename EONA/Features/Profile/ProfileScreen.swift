import PhotosUI
import SwiftUI
import UIKit
import EonaCore
import EonaData

/// « Mon compte & Statistiques », de haut en bas : profil (photo, nom modifiable, statut),
/// comptes liés (Google ; Apple bientôt), statistiques, puis version et suppression du compte.
/// Véhicule : dans Réglages.
struct ProfileScreen: View {
    let services: AppServices

    @State private var photo: PhotosPickerItem?
    @State private var confirmDelete = false
    /// What the Google row is doing, and what it has to say.
    @State private var linking = false
    @State private var linkMessage: String?
    @State private var deleting = false
    @State private var deleteError: String?
    @State private var offers: PaywallReason?
    @State private var renaming = false
    @State private var stats: AccountStats?
    @State private var statsLoaded = false

    private static let version: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }()

    var body: some View {
        let account = services.account.account
        Form {
            Section {
                header(account)
                if account?.isRestricted == true {
                    Text("Navigation et signalements : avec EONA +.")
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textSecondary)
                } else if account?.role == .guest {
                    Text("Essai 7 jours · \(account?.limits?.reportsPerDay ?? 5) signalements et \(account?.limits?.tripsPerDay ?? 7) trajets par jour.")
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textSecondary)
                }
            }

            if account?.email != nil && account?.emailVerified == false {
                Section {
                    VerifyEmailForm(account: services.account)
                }
            }

            Section {
                if GoogleAuth.isAvailable {
                    googleRow
                    if let linkMessage {
                        Text(linkMessage)
                            .font(.xrFootnote)
                            .foregroundStyle(EonaColor.textSecondary)
                    }
                }
                LinkedAccountRow(mark: .symbol(.appleLogo), title: "Apple", subtitle: nil) {
                    EonaBadge(text: "Bientôt", color: EonaColor.textTertiary)
                }
                .accessibilityElement(children: .combine)
            } header: {
                Text("Comptes liés")
            }

            StatsSections(stats: stats, loaded: statsLoaded)

            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Text(deleting ? "Suppression…" : "Supprimer mon compte")
                        .font(.xrBodyStrong)
                        .foregroundStyle(EonaColor.danger)
                        .frame(maxWidth: .infinity)
                }
                .disabled(deleting)
            } footer: {
                VStack(spacing: EonaSpacing.xs) {
                    if let deleteError {
                        Text(deleteError)
                            .foregroundStyle(EonaColor.danger)
                    }
                    Text("EONA \(Self.version)")
                        .foregroundStyle(EonaColor.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, EonaSpacing.sm)
            }
        }
        .scrollContentBackground(.hidden)
        .background(EonaColor.canvas)
        .navigationTitle("Mon compte & Statistiques")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            stats = await StatsSections.load(account: services.account, history: services.trips)
            statsLoaded = true
        }
        .alert("Supprimer ton compte ?", isPresented: $confirmDelete) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer définitivement", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("Compte, photo, statistiques et trajets effacés pour de bon. Tes signalements restent, sans ton nom.")
        }
        .sheet(item: $offers) { reason in
            OffersSheet(reason: reason, account: services.account.account)
        }
        .sheet(isPresented: $renaming) {
            UsernameSheet(account: services.account)
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    /// Photo (touchée : changée, ou offre membre), nom (crayon : pseudo, une fois par semaine),
    /// statut.
    @ViewBuilder
    private func header(_ account: Account?) -> some View {
        let role = account?.role ?? .guest
        let name = displayName(of: account)
        let canEdit = account?.canEditProfile == true
        let access = AccountLabels.access(account, nowMillis: nowMillis())
        let wait = AccountLabels.usernameChange(account, nowMillis: nowMillis())
        HStack(spacing: EonaSpacing.md) {
            Group {
                if canEdit {
                    PhotosPicker(selection: $photo, matching: .images) {
                        avatar(account, name: name, editable: true)
                    }
                    .accessibilityLabel("Changer la photo")
                } else {
                    Button {
                        offers = .photo
                    } label: {
                        avatar(account, name: name, editable: false)
                    }
                    .accessibilityLabel("Photo réservée aux membres")
                }
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: EonaSpacing.xs) {
                // Nom touché : pseudo changé. Client actif seulement, une fois par semaine (backend) ;
                // sinon l'offre EONA +.
                let canRename = account?.canChangeUsername == true
                Button {
                    if canRename { renaming = true } else { offers = .username }
                } label: {
                    HStack(spacing: EonaSpacing.xs) {
                        Text(name)
                            .font(.xrTitle)
                            .foregroundStyle(EonaColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Image(EonaSymbol.edit)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(canRename && wait == nil ? EonaColor.accent : EonaColor.textTertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .disabled(canRename && wait != nil)
                .accessibilityLabel("\(name), changer de pseudo")
                HStack(spacing: EonaSpacing.sm) {
                    EonaBadge(text: role.label, glow: true)
                    if access != role.label {
                        Text(access)
                            .font(.xrFootnote)
                            .foregroundStyle(EonaColor.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                if let wait {
                    Text(wait)
                        .font(.xrCaption)
                        .foregroundStyle(EonaColor.textTertiary)
                }
            }
        }
        .padding(.vertical, EonaSpacing.xs)
    }

    /// L'avatar ; modifiable : petit appareil photo en coin.
    private func avatar(_ account: Account?, name: String, editable: Bool) -> some View {
        AvatarView(url: account?.avatarUrl, initial: name, size: 72)
            .overlay(alignment: .bottomTrailing) {
                if editable {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EonaColor.onAccent)
                        .frame(width: 24, height: 24)
                        .background(EonaColor.accent, in: .circle)
                        .overlay { Circle().strokeBorder(EonaColor.canvas, lineWidth: 2) }
                }
            }
    }

    /// Linked or not, with the one action that makes sense.
    /// Dissociation refusée par le serveur s'il ne reste aucun autre moyen de connexion.
    @ViewBuilder
    private var googleRow: some View {
        let linked = services.account.account?.providers.contains("google") == true
        Button {
            linked ? unlinkGoogle() : linkGoogle()
        } label: {
            LinkedAccountRow(mark: nil, title: "Google", subtitle: linked ? "Lié" : "Non lié") {
                if linking {
                    ProgressView().tint(EonaColor.accent)
                } else {
                    Text(linked ? "Dissocier" : "Lier")
                        .font(.xrLabel)
                        .foregroundStyle(linked ? EonaColor.textSecondary : EonaColor.accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .disabled(linking)
    }

    private func linkGoogle() {
        linking = true
        Task {
            linkMessage = nil
            switch await GoogleAuth.identityToken() {
            case .failure(let message):
                if !message.isEmpty { linkMessage = message }
            case .success(let token):
                linkMessage = await services.account.linkGoogle(idToken: token) ?? "Compte Google lié."
            }
            linking = false
        }
    }

    private func unlinkGoogle() {
        linking = true
        Task {
            linkMessage = await services.account.unlinkGoogle() ?? "Compte Google dissocié."
            GoogleAuth.signOut()
            linking = false
        }
    }

    private func deleteAccount() async {
        deleting = true
        deleteError = nil
        if let error = await services.account.deleteAccount() {
            deleteError = error
        } else {
            services.trips.removeAll()
        }
        deleting = false
    }

    private func upload(_ item: PhotosPickerItem) async {
        defer { photo = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let encoded = await Task.detached(priority: .userInitiated) {
            ProfileScreen.encodeAvatar(data)
        }.value
        guard let encoded else { return }
        _ = await services.account.uploadAvatar(dataUrl: encoded)
    }

    /// The picked image, downscaled to 256 px at most, as a JPEG data URL, like Android.
    nonisolated private static func encodeAvatar(_ data: Data) -> String? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, 256 / max(image.size.width, image.size.height))
        let size = CGSize(
            width: max((image.size.width * scale).rounded(.down), 1),
            height: max((image.size.height * scale).rounded(.down), 1)
        )
        guard let jpeg = (image.preparingThumbnail(of: size) ?? image).jpegData(compressionQuality: 0.82) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}

/// Email not verified yet: the code received by email, or a new one.
private struct VerifyEmailForm: View {
    let account: AccountStore

    @State private var code = ""
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.sm) {
            Text("Email non vérifié")
                .font(.xrHeadline)
                .foregroundStyle(EonaColor.textPrimary)
            Text("Entre le code reçu par email.")
                .font(.xrSubhead)
                .foregroundStyle(EonaColor.textSecondary)
            TextField("Code à 6 chiffres", text: $code)
                .font(.xrBody)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .padding(EonaSpacing.md)
                .background(EonaColor.surface, in: .rect(cornerRadius: EonaRadius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: EonaRadius.md).strokeBorder(EonaColor.border, lineWidth: 1)
                }
                .onChange(of: code) { _, value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed != value { code = trimmed }
                }
            HStack(spacing: EonaSpacing.sm) {
                EonaButton(title: "Vérifier", fillWidth: true) {
                    Task { message = await account.verifyEmail(code: code) ?? "Email vérifié ✓" }
                }
                EonaButton(title: "Renvoyer", variant: .secondary, fillWidth: true) {
                    Task {
                        await account.resendVerify()
                        message = "Code renvoyé."
                    }
                }
            }
            if let message {
                Text(message)
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.accent)
            }
        }
        .padding(.vertical, EonaSpacing.xs)
    }
}

/// Un compte lié : sa marque (symbole, ou initiale), son nom, son état, une action.
private struct LinkedAccountRow<Trailing: View>: View {
    let mark: EonaIconImage?
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: EonaSpacing.md) {
            Group {
                if let mark {
                    EonaIconView(icon: mark, size: 17)
                } else {
                    Text(String(title.prefix(1)))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(EonaColor.textPrimary)
            .frame(width: 30, height: 30)
            .background(EonaColor.textPrimary.opacity(0.08), in: .rect(cornerRadius: EonaRadius.sm))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.xrBody)
                    .foregroundStyle(EonaColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.textTertiary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}
