import GoogleSignIn
import SwiftUI
import UIKit
import EonaData

/// "Se connecter avec Google". The phone only collects an identity token; whether it is genuine,
/// who it belongs to and whether that person already has an account is decided by our server —
/// nothing here is taken on trust.
///
/// Without a client id in Info.plist (`GoogleClientID`), the button is not shown at all.
@MainActor
enum GoogleAuth {
    /// The client id of this app, set in Info.plist from the xcconfig. Empty: Google is off.
    static var clientID: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String ?? ""
        return value.trimmingCharacters(in: .whitespaces)
    }

    static var isAvailable: Bool { !clientID.isEmpty }

    /// Opens Google's own sheet and hands back the identity token, or nil when the driver closed it.
    static func identityToken() async -> Result<String, String> {
        guard isAvailable else { return .failure("Google n'est pas configuré dans cette version.") }
        guard let presenter = topViewController() else { return .failure("Écran indisponible.") }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let token = result.user.idToken?.tokenString else {
                return .failure("Google n'a pas renvoyé d'identité.")
            }
            return .success(token)
        } catch let error as NSError {
            // The driver closing the sheet is not a failure worth shouting about.
            if error.code == GIDSignInError.canceled.rawValue { return .failure("") }
            return .failure("Connexion Google impossible.")
        }
    }

    /// Forgets the Google session on this phone, without touching the EONA account.
    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    /// What Google needs to present its sheet on.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

/// The button, as Google asks it to look: its mark, one line, the app's own shapes around it.
struct GoogleSignInButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: EonaSpacing.sm) {
                GoogleMark()
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.xrBodyStrong)
                    .foregroundStyle(EonaColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, EonaSpacing.md)
            .background(EonaColor.surface, in: .rect(cornerRadius: EonaRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: EonaRadius.md).strokeBorder(EonaColor.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Google's four-colour mark, drawn rather than shipped as an image.
private struct GoogleMark: View {
    var body: some View {
        ZStack {
            Circle().trim(from: 0.0, to: 0.25).stroke(Color(red: 0.92, green: 0.26, blue: 0.21), lineWidth: 4)
            Circle().trim(from: 0.25, to: 0.5).stroke(Color(red: 0.98, green: 0.74, blue: 0.02), lineWidth: 4)
            Circle().trim(from: 0.5, to: 0.75).stroke(Color(red: 0.20, green: 0.66, blue: 0.33), lineWidth: 4)
            Circle().trim(from: 0.75, to: 1.0).stroke(Color(red: 0.26, green: 0.52, blue: 0.96), lineWidth: 4)
        }
        .rotationEffect(.degrees(-90))
        .padding(2)
    }
}
