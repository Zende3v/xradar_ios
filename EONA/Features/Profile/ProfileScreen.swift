import PhotosUI
import SwiftUI
import UIKit
import EonaCore
import EonaData

/// "Mon compte": name, role and photo (members change it), "Changer de pseudo" (clients with
/// access), access status, email verification, the guest's trial note and the app version.
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

    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"

    var body: some View {
        let account = services.account.account
        Form {
            Section {
                header(account)
            }

            // Only a client whose access runs, as the backend says; once a week.
            if account?.canChangeUsername == true {
                Section {
                    let wait = AccountLabels.usernameChange(account, nowMillis: nowMillis())
                    Button {
                        renaming = true
                    } label: {
                        EonaListRow(
                            title: "Changer de pseudo",
                            subtitle: wait ?? "Une fois par semaine",
                            icon: .symbol(.edit),
                            tint: EonaColor.accent
                        )
                        .contentShape(.rect)
                    }
                    .buttonStyle(.borderless)
                    .disabled(wait != nil)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: EonaSpacing.xs) {
                    Text("Statut")
                        .font(.xrCaption)
                        .foregroundStyle(EonaColor.textTertiary)
                    Text(AccountLabels.access(account, nowMillis: nowMillis()))
                        .font(.xrHeadline)
                        .foregroundStyle(EonaColor.textPrimary)
                    if account?.isRestricted == true {
                        Text("La carte reste disponible ; la navigation et les signalements reviennent avec un abonnement.")
                            .font(.xrSubhead)
                            .foregroundStyle(EonaColor.textSecondary)
                    }
                }
            }

            if account?.email != nil && account?.emailVerified == false {
                Section {
                    VerifyEmailForm(account: services.account)
                }
            }

            if account?.role == .guest {
                Section {
                    Text("Compte invité : 7 jours d'essai gratuit, \(account?.limits?.reportsPerDay ?? 5) signalements et \(account?.limits?.tripsPerDay ?? 7) trajets par jour. Ensuite, la carte seule sans abonnement.")
                        .font(.xrSubhead)
                        .foregroundStyle(EonaColor.textSecondary)
                }
            }

            if GoogleAuth.isAvailable {
                Section {
                    googleRow
                    if let linkMessage {
                        Text(linkMessage)
                            .font(.xrFootnote)
                            .foregroundStyle(EonaColor.textSecondary)
                    }
                } header: {
                    Text("Connexion")
                } footer: {
                    Text("Lier Google te laisse entrer d'un geste. La dissociation est refusée s'il ne te reste aucun autre moyen de te connecter.")
                }
            }

            Section {
                LabeledContent("Version", value: Self.version)
            }

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
                if let deleteError {
                    Text(deleteError)
                        .foregroundStyle(EonaColor.danger)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(EonaColor.canvas)
        .navigationTitle("Mon compte")
        .alert("Supprimer ton compte ?", isPresented: $confirmDelete) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer définitivement", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("Ton compte, ta photo, tes statistiques et tes trajets sont effacés pour de bon. Tes signalements restent pour les autres conducteurs, sans ton nom.")
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

    @ViewBuilder
    private func header(_ account: Account?) -> some View {
        let role = account?.role ?? .guest
        let name = displayName(of: account)
        let canEdit = account?.canEditProfile == true
        HStack(spacing: EonaSpacing.md) {
            if canEdit {
                PhotosPicker(selection: $photo, matching: .images) {
                    AvatarView(url: account?.avatarUrl, initial: name, size: 64)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Changer la photo")
            } else {
                Button {
                    offers = .photo
                } label: {
                    AvatarView(url: account?.avatarUrl, initial: name, size: 64)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Photo de profil réservée aux membres")
            }
            VStack(alignment: .leading, spacing: EonaSpacing.xs) {
                Text(name)
                    .font(.xrTitleLarge)
                    .foregroundStyle(EonaColor.textPrimary)
                EonaBadge(text: role.label, glow: true)
                if canEdit {
                    PhotosPicker("Changer la photo", selection: $photo, matching: .images)
                        .font(.xrCaption)
                        .tint(EonaColor.accent)
                        .buttonStyle(.borderless)
                } else {
                    Button("Photo réservée aux membres") {
                        offers = .photo
                    }
                    .font(.xrCaption)
                    .tint(EonaColor.accent)
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, EonaSpacing.xs)
    }

    /// On success the account is gone: the app goes back to onboarding by itself.
    /// Linked or not, with the one action that makes sense.
    @ViewBuilder
    private var googleRow: some View {
        let linked = services.account.account?.providers.contains("google") == true
        Button {
            linked ? unlinkGoogle() : linkGoogle()
        } label: {
            EonaListRow(
                title: linked ? "Dissocier Google" : "Lier mon compte Google",
                subtitle: linked ? "Ce compte peut se connecter avec Google" : "Pour entrer aussi avec Google"
            ) {
                if linking { ProgressView().tint(EonaColor.accent) }
            }
        }
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
