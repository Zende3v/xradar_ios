import Foundation
import EonaCore

/// Seul expéditeur de la file trajets : trajet, puis tracé par paquets de 1 000 points, dans
/// l'ordre de la file. Chaque passe fige la session (compte, jeton, révision), vérifiée avant
/// chaque requête et après chaque réponse : changée, la passe s'arrête sans rien retirer. Seuls
/// les trajets du compte de cette session partent, jamais sous le jeton d'un autre.
/// Déclencheurs : file nouvelle, réseau revenu, premier plan, session changée. Échec : renvois
/// bornés, délais croissants ; hors réseau, attente du retour réseau. File vide : aucune tâche.
@MainActor
public final class TripOutboxSender {
    public static let tracePointsPerPost = 1_000
    /// Délai avant chaque renvoi après échec ; au-delà, attente du prochain déclencheur.
    public static let retryDelays: [Duration] = [.seconds(30), .seconds(120), .seconds(600)]

    private let outbox: TripOutboxStore
    private let account: AccountStore
    private let api: AccountAPI
    private let sleep: @Sendable (Duration) async throws -> Void
    private var task: Task<Void, Never>?
    private var run = 0
    /// Demande reçue pendant un envoi : nouvelle passe ensuite.
    private var again = false
    /// Dernière session suivie.
    private var session: AccountSession?
    public private(set) var online = true

    public init(
        outbox: TripOutboxStore, account: AccountStore, api: AccountAPI,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.outbox = outbox
        self.account = account
        self.api = api
        self.sleep = sleep
        session = account.session
    }

    /// Envoi en cours ou renvoi en attente.
    public var isSending: Bool { task != nil }

    /// Envoi demandé après [delay]. Envoi déjà en cours : une passe de plus à sa fin.
    public func send(after delay: Duration = .zero) {
        guard task == nil else {
            again = true
            return
        }
        guard online, let current = account.session,
              outbox.pending.contains(where: { $0.accountId == current.accountId })
        else { return }
        run &+= 1
        let id = run
        task = Task { [weak self] in
            await self?.loop(delay: delay)
            self?.finished(id)
        }
    }

    /// Session observée. Changée (déconnexion, autre compte, nouveau jeton) : envoi en cours
    /// annulé, résultats tardifs ignorés, puis reprise pour le compte de la nouvelle session.
    public func follow(_ next: AccountSession?) {
        guard next != session else { return }
        session = next
        stop()
        send()
    }

    /// Réseau disponible ou non. Perte : passe et renvoi en attente annulés, résultats tardifs
    /// ignorés. Retour : nouvelle passe aussitôt, sans attendre l'ancien délai.
    public func setOnline(_ value: Bool) {
        guard value != online else { return }
        online = value
        stop()
        if value { send() }
    }

    /// Tâche en cours annulée, nouvelle génération : sa fin tardive ne touche plus rien.
    private func stop() {
        task?.cancel()
        task = nil
        again = false
        run &+= 1
    }

    private func finished(_ id: Int) {
        guard id == run else { return }
        task = nil
        if again {
            again = false
            send()
        }
    }

    private func loop(delay initial: Duration) async {
        var delay = initial
        var failures = 0
        while true {
            again = false
            if delay > .zero {
                do { try await sleep(delay) } catch { return }
            }
            guard !Task.isCancelled, online, let current = account.session else { return }
            let complete = await pass(current)
            guard valid(current) else { return }
            if complete {
                failures = 0
                delay = .zero
                guard again else { return }
            } else if online, failures < Self.retryDelays.count {
                delay = Self.retryDelays[failures]
                failures += 1
            } else {
                // Renvois épuisés ou hors réseau : seule une demande reçue entre-temps relance.
                guard online, again else { return }
                delay = .zero
            }
        }
    }

    /// Une passe sur la file du compte de [current] ; vrai si tout est parti.
    private func pass(_ current: AccountSession) async -> Bool {
        var complete = true
        for item in outbox.pending where item.accountId == current.accountId {
            let id = item.trip.id
            guard valid(current), outbox.holds(id, accountId: current.accountId) else { return false }
            let posted = await api.postTrip(token: current.token, trip: item.trip, countInStats: item.countInStats)
            guard valid(current) else { return false }
            guard posted else {
                complete = false
                continue
            }
            var sent = true
            let trace = item.trace
            for (seq, start) in stride(from: 0, to: trace.count, by: Self.tracePointsPerPost).enumerated() {
                guard valid(current), outbox.holds(id, accountId: current.accountId) else { return false }
                let chunk = Array(trace[start..<min(start + Self.tracePointsPerPost, trace.count)])
                let ok = await api.postTrace(token: current.token, tripId: id, seq: seq, points: chunk)
                guard valid(current) else { return false }
                if !ok {
                    sent = false
                    break
                }
            }
            if sent { outbox.remove(id) } else { complete = false }
        }
        return complete
    }

    /// Passe toujours légitime : non annulée, réseau présent, même session qu'au départ.
    private func valid(_ current: AccountSession) -> Bool {
        !Task.isCancelled && online && account.session == current
    }
}
