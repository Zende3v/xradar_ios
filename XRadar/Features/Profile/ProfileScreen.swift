import PhotosUI
import SwiftUI
import UIKit
import XRadarCore
import XRadarData

/// "Mon compte": name, role and photo (members change it), access status, email verification,
/// the guest's trial note and the app version.
struct ProfileScreen: View {
    let services: AppServices

    @State private var photo: PhotosPickerItem?
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteError: String?
    @State private var offers: PaywallReason?

    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"

    var body: some View {
        let account = services.account.account
        Form {
            Section {
                header(account)
            }

            Section {
                VStack(alignment: .leading, spacing: XRadarSpacing.xs) {
                    Text("Statut")
                        .font(.xrCaption)
                        .foregroundStyle(XRadarColor.textTertiary)
                    Text(AccountLabels.access(account, nowMillis: nowMillis()))
                        .font(.xrHeadline)
                        .foregroundStyle(XRadarColor.textPrimary)
                    if account?.isRestricted == true {
                        Text("La carte reste disponible ; la navigation et les signalements reviennent avec un abonnement.")
                            .font(.xrSubhead)
                            .foregroundStyle(XRadarColor.textSecondary)
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
                        .foregroundStyle(XRadarColor.textSecondary)
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
                        .foregroundStyle(XRadarColor.danger)
                        .frame(maxWidth: .infinity)
                }
                .disabled(deleting)
            } footer: {
                if let deleteError {
                    Text(deleteError)
                        .foregroundStyle(XRadarColor.danger)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(XRadarColor.canvas)
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
        HStack(spacing: XRadarSpacing.md) {
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
            VStack(alignment: .leading, spacing: XRadarSpacing.xs) {
                Text(name)
                    .font(.xrTitleLarge)
                    .foregroundStyle(XRadarColor.textPrimary)
                XRadarBadge(text: role.label, glow: true)
                if canEdit {
                    PhotosPicker("Changer la photo", selection: $photo, matching: .images)
                        .font(.xrCaption)
                        .tint(XRadarColor.accent)
                        .buttonStyle(.borderless)
                } else {
                    Button("Photo réservée aux membres") {
                        offers = .photo
                    }
                    .font(.xrCaption)
                    .tint(XRadarColor.accent)
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, XRadarSpacing.xs)
    }

    /// On success the account is gone: the app goes back to onboarding by itself.
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
        VStack(alignment: .leading, spacing: XRadarSpacing.sm) {
            Text("Email non vérifié")
                .font(.xrHeadline)
                .foregroundStyle(XRadarColor.textPrimary)
            Text("Entre le code reçu par email.")
                .font(.xrSubhead)
                .foregroundStyle(XRadarColor.textSecondary)
            TextField("Code à 6 chiffres", text: $code)
                .font(.xrBody)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .padding(XRadarSpacing.md)
                .background(XRadarColor.surface, in: .rect(cornerRadius: XRadarRadius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: XRadarRadius.md).strokeBorder(XRadarColor.border, lineWidth: 1)
                }
                .onChange(of: code) { _, value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed != value { code = trimmed }
                }
            HStack(spacing: XRadarSpacing.sm) {
                XRadarButton(title: "Vérifier", fillWidth: true) {
                    Task { message = await account.verifyEmail(code: code) ?? "Email vérifié ✓" }
                }
                XRadarButton(title: "Renvoyer", variant: .secondary, fillWidth: true) {
                    Task {
                        await account.resendVerify()
                        message = "Code renvoyé."
                    }
                }
            }
            if let message {
                Text(message)
                    .font(.xrFootnote)
                    .foregroundStyle(XRadarColor.accent)
            }
        }
        .padding(.vertical, XRadarSpacing.xs)
    }
}
