import AuthenticationServices
import CryptoKit
import Foundation
import UIKit
import EonaData

/// "Connecter Spotify": Spotify's own sign-in page, in a secure web sheet, then tokens kept in
/// the Keychain. PKCE all the way — the app holds no client secret, and nothing goes through
/// EONA's server: the phone talks to Spotify directly.
///
/// Without a client id in Info.plist (`SpotifyClientID`), Spotify is simply not offered.
@MainActor
final class SpotifyAuth {
    /// Declared as is in the Spotify dashboard.
    static let redirectURI = "eona://spotify-callback"
    /// Read what plays, and drive it. Nothing about the library, the playlists or the account.
    static let scopes = ["user-read-playback-state", "user-modify-playback-state", "user-read-currently-playing"]

    static var clientID: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? ""
        return value.trimmingCharacters(in: .whitespaces)
    }

    static var isAvailable: Bool { !clientID.isEmpty }

    private let keychain: any SecretStore
    private var session: Session?
    /// Kept alive while Spotify's page is open.
    private var webSession: ASWebAuthenticationSession?
    private let anchor = AnchorProvider()

    init(keychain: any SecretStore) {
        self.keychain = keychain
        session = Self.load(from: keychain)
    }

    var isSignedIn: Bool { session != nil }

    /// Opens Spotify's sign-in page. Returns a sentence for the driver when it did not work, nil
    /// when it did — or when the driver simply closed the page.
    func signIn() async -> String? {
        guard Self.isAvailable else { return "Spotify n'est pas configuré dans cette version." }
        let verifier = Self.randomString(length: 64)
        let state = Self.randomString(length: 16)
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else { return "Connexion Spotify impossible." }

        let callback: Result<URL, any Error> = await withCheckedContinuation { continuation in
            let web = ASWebAuthenticationSession(url: url, callback: .customScheme("eona")) { url, error in
                if let url {
                    continuation.resume(returning: .success(url))
                } else {
                    continuation.resume(returning: .failure(error ?? URLError(.cancelled)))
                }
            }
            // Signed in to Spotify in Safari already: the page recognises the driver.
            web.prefersEphemeralWebBrowserSession = false
            web.presentationContextProvider = anchor
            webSession = web
            if !web.start() {
                continuation.resume(returning: .failure(URLError(.cannotLoadFromNetwork)))
            }
        }
        webSession = nil

        guard case .success(let returned) = callback else {
            if case .failure(let error) = callback,
               (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                return nil
            }
            return "Connexion Spotify interrompue."
        }
        let items = URLComponents(url: returned, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        guard value("state") == state else { return "Connexion Spotify refusée : réponse inattendue." }
        if let error = value("error") {
            return error == "access_denied" ? nil : "Spotify a refusé la connexion (\(error))."
        }
        guard let code = value("code") else { return "Connexion Spotify impossible." }

        let answer = await Self.token([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": Self.clientID,
            "code_verifier": verifier,
        ])
        guard let fresh = answer else { return "Spotify n'a pas délivré l'accès. Réessaie." }
        store(fresh)
        return nil
    }

    /// Forgets Spotify on this phone. The driver can also withdraw EONA from their Spotify account.
    func signOut() {
        session = nil
        keychain.set(nil, for: Self.key)
    }

    /// A valid access token, refreshed when it is about to run out; nil once Spotify refuses the
    /// refresh (access withdrawn): the driver has to connect again.
    func accessToken() async -> String? {
        guard let current = session else { return nil }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        let answer = await Self.token([
            "grant_type": "refresh_token",
            "refresh_token": current.refreshToken,
            "client_id": Self.clientID,
        ])
        guard let fresh = answer else {
            signOut()
            return nil
        }
        // Spotify may or may not hand a new refresh token; the old one stays good when it does not.
        store(Session(accessToken: fresh.accessToken, refreshToken: fresh.refreshToken.isEmpty ? current.refreshToken : fresh.refreshToken, expiresAt: fresh.expiresAt))
        return fresh.accessToken
    }

    // MARK: Tokens

    private struct Session: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    private static let key = "spotify.session"

    private func store(_ fresh: Session) {
        session = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            keychain.set(String(data: data, encoding: .utf8), for: Self.key)
        }
    }

    private static func load(from keychain: any SecretStore) -> Session? {
        guard let text = keychain.string(for: key) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: Data(text.utf8))
    }

    /// The token endpoint, form-encoded as Spotify asks.
    private static func token(_ form: [String: String]) async -> Session? {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String
        else { return nil }
        let seconds = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return Session(
            accessToken: access,
            refreshToken: json["refresh_token"] as? String ?? "",
            expiresAt: Date().addingTimeInterval(seconds)
        )
    }

    // MARK: PKCE

    private static func randomString(length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int(generator.next(upperBound: UInt(alphabet.count)))] })
    }

    private static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// The window Spotify's page opens over.
private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
