/// Commande demandée et observation distinctes. Getter faible ne remplace jamais événement direct.
nonisolated struct SystemMediaPlaybackState: Sendable {
    private(set) var observed: Bool?
    private(set) var requested: Bool?
    private var hasDirectEvent = false

    var displayed: Bool? { requested ?? observed }
    var requestDescription: String? {
        requested.map { $0 ? "Lecture demandée" : "Pause demandée" }
    }

    mutating func request(_ playing: Bool) { requested = playing }
    mutating func cancelRequest() { requested = nil }

    mutating func observeEvent(_ playing: Bool) {
        observed = playing
        requested = nil
        hasDirectEvent = true
    }

    mutating func observeSnapshot(_ playing: Bool?, reliable: Bool) {
        guard reliable, let playing else { return }
        guard !hasDirectEvent || requested != nil else { return }
        // Relevé transitoire contradictoire ne confirme aucune commande.
        guard requested == nil || requested == playing else { return }
        observed = playing
        requested = nil
    }

    mutating func reset() {
        observed = nil
        requested = nil
        hasDirectEvent = false
    }
}
