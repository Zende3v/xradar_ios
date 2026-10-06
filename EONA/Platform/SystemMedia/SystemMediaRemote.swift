import Observation
import UIKit
import ImageIO
import AVFAudio

/// Piste prioritaire. Repli temporel uniquement avec intervalle annoncé par lecteur.
enum SystemMediaNavigation: Equatable {
    case track
    case skip(seconds: Double)
    case unavailable

    static func resolve(track: Bool?, skip: Bool?, interval: Double?) -> Self {
        guard let track else { return .track } // Accès capacités absent : essai réel, sans effet prétendu.
        if track { return .track }
        if skip == true, let interval, interval.isFinite, interval > 0 { return .skip(seconds: interval) }
        return .unavailable
    }
}

/// Valeurs immuables : objet Objective-C reste dans callback, jamais transféré vers acteur UI.
private nonisolated struct SystemMediaSnapshot: Sendable {
    let title: String?
    let artist: String?
    let artwork: Data?
    let playing: Bool?
    let commands: [Int: Bool]?
    let forwardInterval: Double?
    let backwardInterval: Double?

    init(_ raw: EONASystemMediaSnapshot) {
        title = raw.title
        artist = raw.artist
        artwork = raw.artwork
        playing = raw.playing?.boolValue
        commands = raw.commands.map { values in
            Dictionary(uniqueKeysWithValues: values.map { ($0.key.intValue, $0.value.boolValue) })
        }
        forwardInterval = raw.forwardInterval?.doubleValue
        backwardInterval = raw.backwardInterval?.doubleValue
    }
}

/// Lecteur actif global. État observé ; aucune bascule optimiste ni second envoi automatique.
@MainActor
@Observable
final class SystemMediaRemote {
    private(set) var playback: MusicPlayback = .systemControls(title: nil, artist: nil, artwork: nil, isPlaying: nil)
    private(set) var notice: String?
    private(set) var busy = false
    private(set) var nextNavigation: SystemMediaNavigation = .track
    private(set) var previousNavigation: SystemMediaNavigation = .track
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var commandTask: Task<Void, Never>?
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var pendingRefresh = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var stateRevision = 0
    @ObservationIgnored private var commandRevision = 0
    @ObservationIgnored private var artworkData: Data?
    @ObservationIgnored private var artworkImage: UIImage?
    @ObservationIgnored private var snapshot: SystemMediaSnapshot?
    @ObservationIgnored private var stateFresh = false
    @ObservationIgnored private var audioObserved = false

    var available: Bool { EONASystemMedia.isEnabled() }

    func start() {
        guard available, !visible else { return }
        visible = true
        guard EONASystemMedia.prepare() else {
            playback = .unavailable("Lecteur système inaccessible sur cet iPhone.")
            return
        }
        EONASystemMedia.beginObserving { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        visible = false
        revision += 1
        commandRevision += 1
        refreshing = false
        pendingRefresh = false
        busy = false
        audioObserved = false
        snapshot = nil
        stateFresh = false
        notice = nil
        nextNavigation = .track
        previousNavigation = .track
        EONASystemMedia.endObserving()
        polling?.cancel()
        polling = nil
        commandTask?.cancel()
        commandTask = nil
    }

    func retry() {
        stop()
        start()
    }

    func refresh() {
        guard visible else { return }
        publishPlayback()
        guard !refreshing else {
            pendingRefresh = true
            return
        }
        guard EONASystemMedia.prepare() else {
            playback = .unavailable("Lecteur système inaccessible sur cet iPhone.")
            return
        }
        refreshing = true
        let request = revision
        let requestedState = stateRevision
        EONASystemMedia.read { [weak self] raw in
            let snapshot = SystemMediaSnapshot(raw)
            // Adaptateur garantit callback sur file principale, y compris timeout et refus.
            MainActor.assumeIsolated {
                guard let self, self.visible, self.revision == request else { return }
                self.refreshing = false
                if requestedState == self.stateRevision {
                    self.snapshot = snapshot
                    self.stateFresh = true
                    if snapshot.artwork != self.artworkData {
                        self.artworkData = snapshot.artwork
                        self.artworkImage = snapshot.artwork.flatMap(Self.thumbnail)
                    }
                    self.nextNavigation = Self.navigation(snapshot, track: .next, skip: .skipForward, interval: snapshot.forwardInterval)
                    self.previousNavigation = Self.navigation(snapshot, track: .previous, skip: .skipBackward, interval: snapshot.backwardInterval)
                    self.publishPlayback()
                } else {
                    self.pendingRefresh = true
                }
                if self.pendingRefresh {
                    self.pendingRefresh = false
                    self.refresh()
                }
            }
        }
    }

    func playPause() { command(.toggle) }
    func next() { navigate(nextNavigation, track: .next, skip: .skipForward) }
    func previous() { navigate(previousNavigation, track: .previous, skip: .skipBackward) }

    private static func navigation(_ snapshot: SystemMediaSnapshot, track: EONASystemMediaCommand,
                                   skip: EONASystemMediaCommand, interval: Double?) -> SystemMediaNavigation {
        func enabled(_ command: EONASystemMediaCommand) -> Bool? {
            guard let commands = snapshot.commands else { return nil }
            return commands[command.rawValue] ?? false
        }
        return .resolve(track: enabled(track), skip: enabled(skip), interval: interval)
    }

    private func publishPlayback() {
        // API publique : activité audio autre app, aucun changement de session audio EONA.
        // Repli peut refléter buffering/interruption ; ne confirme jamais succès commande.
        let otherAudio = AVAudioSession.sharedInstance().isOtherAudioPlaying
        if otherAudio { audioObserved = true }
        let reported = stateFresh ? snapshot?.playing : nil
        let playing = reported ?? (audioObserved ? otherAudio : nil)
        playback = .systemControls(title: snapshot?.title, artist: snapshot?.artist,
                                   artwork: snapshot == nil ? nil : artworkImage, isPlaying: playing)
    }

    private func navigate(_ navigation: SystemMediaNavigation, track: EONASystemMediaCommand, skip: EONASystemMediaCommand) {
        switch navigation {
        case .track: command(track)
        case .skip(let seconds): command(skip, interval: seconds)
        case .unavailable: break
        }
    }

    private static func thumbnail(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 192,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    private func command(_ command: EONASystemMediaCommand, interval: Double? = nil) {
        guard visible, !busy else { return }
        commandRevision += 1
        let request = commandRevision
        stateRevision += 1 // Lecture commencée avant clic ne remplace pas nouvel état.
        stateFresh = false
        notice = nil
        busy = true
        let accepted = EONASystemMedia.send(command, interval: interval.map { NSNumber(value: $0) }) { [weak self] error, statuses in
            let errorCode = error?.uint32Value
            let statusCodes = statuses?.map(\.intValue)
            MainActor.assumeIsolated {
                guard let self, self.visible, self.commandRevision == request else { return }
                if let errorCode, errorCode != 0 {
                    self.notice = "Commande refusée par le lecteur."
                } else if let statusCodes, !statusCodes.isEmpty,
                          !statusCodes.contains(where: { $0 == 0 || $0 == 3 }) {
                    self.notice = "Commande indisponible dans ce lecteur."
                }
                self.refresh()
            }
        }
        guard accepted else {
            commandRevision += 1
            busy = false
            stateFresh = true
            notice = "Commande refusée par iOS."
            publishPlayback()
            return
        }
        refresh()
        commandTask?.cancel()
        commandTask = Task { [weak self] in
            // Relevés après transition audio ; notification ou callback en cours garde demande suivante.
            for delay in [250, 350, 700] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, let self, self.visible, self.commandRevision == request else { return }
                self.publishPlayback()
                self.refresh()
                if delay == 350 { self.busy = false }
            }
        }
    }
}
