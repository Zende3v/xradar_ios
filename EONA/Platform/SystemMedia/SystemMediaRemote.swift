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
    @ObservationIgnored private var snapshot: EONASystemMediaSnapshot?
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
        EONASystemMedia.read { [weak self] snapshot in
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

    private static func navigation(_ snapshot: EONASystemMediaSnapshot, track: EONASystemMediaCommand,
                                   skip: EONASystemMediaCommand, interval: NSNumber?) -> SystemMediaNavigation {
        func enabled(_ command: EONASystemMediaCommand) -> Bool? {
            guard let commands = snapshot.commands else { return nil }
            return commands[NSNumber(value: command.rawValue)]?.boolValue ?? false
        }
        return .resolve(track: enabled(track), skip: enabled(skip), interval: interval?.doubleValue)
    }

    private func publishPlayback() {
        // API publique : activité audio autre app, aucun changement de session audio EONA.
        // Repli peut refléter buffering/interruption ; ne confirme jamais succès commande.
        let otherAudio = AVAudioSession.sharedInstance().isOtherAudioPlaying
        if otherAudio { audioObserved = true }
        let reported = stateFresh ? snapshot?.playing?.boolValue : nil
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
            MainActor.assumeIsolated {
                guard let self, self.visible, self.commandRevision == request else { return }
                if let error, error.uint32Value != 0 {
                    self.notice = "Commande refusée par le lecteur."
                } else if let statuses, !statuses.isEmpty,
                          !statuses.contains(where: { $0.intValue == 0 || $0.intValue == 3 }) {
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
