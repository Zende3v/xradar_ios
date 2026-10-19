import Foundation
import Testing
import EonaCore
@testable import EonaData

private let registrationBody = #"{"verificationRequired":true,"registration":{"email":"owner@example.test","registrationToken":"challenge","guestId":"guest","expiresAt":"2099-10-19T20:30:00.000Z","resendAt":"2099-10-19T20:01:00.000Z"}}"#
private let verifiedBody = #"{"account":{"id":"guest","role":"client","username":"driver","email":"owner@example.test","emailVerified":true,"access":"trial"},"token":"guest-token"}"#
private let guestBody = #"{"account":{"id":"guest","role":"guest","username":"Invite_123","access":"free"},"token":"guest-token"}"#

struct RegistrationAPITests {
    @Test func registrationWaitsForEmailAndNeverAcceptsLegacySuccess() async throws {
        let transport = StubTransport(status: 202, body: registrationBody)
        let result = await AccountAPI(client: backend(transport)).register(
            email: "owner@example.test", password: "password-123", username: "driver", referralCode: nil, guestToken: "guest-token"
        )
        guard case .verificationRequired(let pending) = result else { Issue.record("Vérification attendue"); return }
        #expect(pending.email == "owner@example.test")
        #expect(pending.registrationToken == "challenge")
        #expect(pending.guestAccountId == "guest")
        #expect(pending.expiresAt > pending.resendAt)
        #expect(transport.last?.path == "/api/accounts/me/registration")
        #expect(transport.last?.bearer == "Bearer guest-token")
        let legacy = await AccountAPI(client: backend(StubTransport(status: 201, body: verifiedBody))).register(
            email: "owner@example.test", password: "password-123", username: "driver", referralCode: nil
        )
        guard case .failure = legacy else { Issue.record("Ancien contrat refusé"); return }
        let oldServer = StubTransport(status: 404, body: "")
        let unavailable = await AccountAPI(client: backend(oldServer)).register(
            email: "owner@example.test", password: "password-123", username: "driver", referralCode: nil
        )
        #expect(oldServer.last?.path == "/api/accounts/registration")
        #expect(unavailable == RegistrationOutcome.failure("Le serveur doit être mis à jour pour vérifier l'email."))
    }

    @Test func verificationRequiresMemberSessionAndGuestIdentity() async throws {
        let json = try #require(JSON(data: Data(registrationBody.utf8)))
        let pending = try #require(AccountAPI.registration(json))
        let transport = StubTransport(status: 200, body: verifiedBody)
        let result = await AccountAPI(client: backend(transport)).verifyRegistration(pending, code: "123456", guestToken: "guest-token")
        guard case .success(let auth) = result else { Issue.record("Compte vérifié attendu"); return }
        #expect(auth.account.id == "guest")
        #expect(transport.last?.jsonBody["registrationToken"] as? String == "challenge")
        #expect(transport.last?.jsonBody["code"] as? String == "123456")
        #expect(transport.last?.bearer == "Bearer guest-token")
        for body in [guestBody, #"{"account":{"id":"guest","role":"client","emailVerified":true}}"#,
                     #"{"account":{"id":"other","role":"client","emailVerified":true},"token":"other-token"}"#] {
            let invalid = await AccountAPI(client: backend(StubTransport(body: body))).verifyRegistration(pending, code: "123456", guestToken: "guest-token")
            #expect(invalid == AuthOutcome.failure("Réponse invalide"))
        }
    }

    @Test func mailAndExpiryErrorsAreReadable() {
        #expect(AccountAPI.friendly("verified email required") == "Utilise une adresse vérifiée par Google.")
        #expect(AccountAPI.friendly("registration expired") == "Code expiré. Recommence l'inscription.")
        #expect(AccountAPI.friendly("email delivery unavailable") == "Envoi de l'email indisponible. Réessaie.")
    }
}

/// Vérification retenue pour simuler annulation ou connexion à un autre compte pendant l'envoi.
private final class RegistrationTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var held: CheckedContinuation<Void, Never>?
    private var holdsVerification = false

    func holdVerification() { lock.withLock { holdsVerification = true } }
    var isWaiting: Bool { lock.withLock { held != nil } }
    func release() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { held = nil; holdsVerification = false }
            return held
        }
        continuation?.resume()
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.path
        if path == "/api/accounts/verify", lock.withLock({ holdsVerification }) {
            await withCheckedContinuation { continuation in lock.withLock { held = continuation } }
        }
        let status: Int
        let body: String
        switch path {
        case "/api/accounts/registration", "/api/accounts/me/registration", "/api/accounts/resend-verify":
            status = 202; body = registrationBody
        case "/api/accounts/verify": status = 200; body = verifiedBody
        case "/api/accounts/login":
            status = 200; body = #"{"account":{"id":"other","role":"client","username":"other","access":"free"},"token":"other-token"}"#
        default: status = 200; body = guestBody
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}

@MainActor
struct RegistrationStoreTests {
    func make(_ transport: any HTTPTransport, secrets: MemorySecrets, defaults: UserDefaults) -> AccountStore {
        AccountStore(api: AccountAPI(client: BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://example.org/")!), transport: transport
        )), secrets: secrets, defaults: defaults)
    }

    @Test func pendingSurvivesRelaunchWithoutReplacingGuest() async throws {
        let secrets = MemorySecrets()
        let defaults = freshDefaults()
        let transport = RegistrationTransport()
        let store = make(transport, secrets: secrets, defaults: defaults)
        store.restore()
        _ = await store.claimGuest()
        let session = store.session
        _ = await store.register(email: "owner@example.test", password: "password-123", username: "driver")
        #expect(store.account?.isGuest == true)
        #expect(store.session == session)
        #expect(store.pendingRegistration?.email == "owner@example.test")
        #expect(secrets.values["pending_registration"]?.contains("password-123") == false)
        let restored = make(transport, secrets: secrets, defaults: defaults)
        restored.restore()
        #expect(restored.account?.id == "guest")
        #expect(restored.pendingRegistration == store.pendingRegistration)
        #expect(await restored.verifyRegistration(code: "123456") == nil)
        #expect(restored.account?.id == "guest")
        #expect(restored.account?.isGuest == false)
        #expect(restored.account?.emailVerified == true)
        #expect(restored.token == "guest-token")
        #expect(restored.pendingRegistration == nil)
        #expect(secrets.values["pending_registration"] == nil)
    }

    @Test func cancellingKeepsGuestAndDiscardsLateVerification() async {
        let transport = RegistrationTransport()
        let store = make(transport, secrets: MemorySecrets(), defaults: freshDefaults())
        _ = await store.claimGuest()
        _ = await store.register(email: "owner@example.test", password: "password-123", username: "driver")
        let original = store.session
        transport.holdVerification()
        let verifying = Task { await store.verifyRegistration(code: "123456") }
        await waitUntil { transport.isWaiting }
        store.cancelRegistration()
        transport.release()
        _ = await verifying.value
        #expect(store.account?.isGuest == true)
        #expect(store.session == original)
        #expect(store.pendingRegistration == nil)
    }

    @Test func anotherLoginWinsOverLateVerification() async {
        let transport = RegistrationTransport()
        let store = make(transport, secrets: MemorySecrets(), defaults: freshDefaults())
        _ = await store.claimGuest()
        _ = await store.register(email: "owner@example.test", password: "password-123", username: "driver")
        transport.holdVerification()
        let verifying = Task { await store.verifyRegistration(code: "123456") }
        await waitUntil { transport.isWaiting }
        _ = await store.login(identifier: "other", password: "password-123")
        transport.release()
        _ = await verifying.value
        #expect(store.account?.id == "other")
        #expect(store.token == "other-token")
        #expect(store.pendingRegistration == nil)
    }

    @Test func failedMailNeverReplacesGuest() async {
        let transport = StubTransport { request in
            request.path == "/api/accounts/guest" ? (201, guestBody) : (503, #"{"error":"email delivery unavailable"}"#)
        }
        let store = make(transport, secrets: MemorySecrets(), defaults: freshDefaults())
        _ = await store.claimGuest()
        let session = store.session
        _ = await store.register(email: "owner@example.test", password: "password-123", username: "driver")
        #expect(store.session == session)
        #expect(store.account?.isGuest == true)
        #expect(store.pendingRegistration == nil)
    }

    @Test func refreshRecoversConversionAfterLostResponse() async {
        let transport = StubTransport { request in
            switch request.path {
            case "/api/accounts/guest": (201, guestBody)
            case "/api/accounts/me": (200, verifiedBody)
            default: (202, registrationBody)
            }
        }
        let store = make(transport, secrets: MemorySecrets(), defaults: freshDefaults())
        _ = await store.claimGuest()
        _ = await store.register(email: "owner@example.test", password: "password-123", username: "driver")
        #expect(store.pendingRegistration != nil)
        await store.refresh()
        #expect(store.pendingRegistration == nil)
        #expect(store.account?.id == "guest")
        #expect(store.account?.emailVerified == true)
        #expect(store.token == "guest-token")
    }
}
