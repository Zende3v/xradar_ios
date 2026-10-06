import Observation
import UIKit
import ImageIO

/// Lecteur actif global. Expérience IPA interne ; refus iOS visible, aucune modification optimiste.
@MainActor
@Observable
final class SystemMediaRemote {
    private(set) var playback: MusicPlayback = .systemControls(title: nil, artist: nil, artwork: nil, isPlaying: nil)
    private(set) var notice: String?
    private(set) var busy = false
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var commandTask: Task<Void, Never>?
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var artworkData: Data?
    @ObservationIgnored private var artworkImage: UIImage?
    @ObservationIgnored private var commandRefused = false

    var available: Bool { EONASystemMedia.isEnabled() }

    func start() {
        guard available, !visible else { return }
        visible = true
        guard EONASystemMedia.prepare() else {
            playback = .unavailable("Lecteur système inaccessible sur cet iPhone.")
            return
        }
        refresh()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        visible = false
        revision += 1
        refreshing = false
        busy = false
        polling?.cancel()
        polling = nil
        commandTask?.cancel()
        commandTask = nil
    }

    func retry() {
        stop()
        commandRefused = false
        notice = nil
        start()
    }

    func refresh() {
        guard visible, !refreshing else { return }
        guard EONASystemMedia.prepare() else {
            playback = .unavailable("Lecteur système inaccessible sur cet iPhone.")
            return
        }
        refreshing = true
        let request = revision
        EONASystemMedia.read { [weak self] title, artist, data, playing in
            // Adaptateur garantit callback sur file principale, y compris timeout et refus.
            MainActor.assumeIsolated {
                guard let self, self.visible, self.revision == request else { return }
                self.refreshing = false
                if data != self.artworkData {
                    self.artworkData = data
                    self.artworkImage = data.flatMap(Self.thumbnail)
                }
                let artwork = self.artworkImage
                self.playback = .systemControls(title: title, artist: artist, artwork: artwork, isPlaying: playing?.boolValue)
                guard !self.commandRefused else { return }
                if title == nil && artist == nil && artwork == nil {
                    self.notice = "Informations du lecteur indisponibles."
                } else if self.notice == "Informations du lecteur indisponibles." {
                    self.notice = nil
                }
            }
        }
    }

    func playPause() { command(.toggle) }
    func next() { command(.next) }
    func previous() { command(.previous) }

    private static func thumbnail(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 192,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    private func command(_ command: EONASystemMediaCommand) {
        guard visible, !busy else { return }
        guard EONASystemMedia.send(command) else {
            commandRefused = true
            notice = "Commande refusée par iOS."
            return
        }
        // Envoi accepté ne démontre aucun effet : aucun état de lecture ni titre fabriqué.
        commandRefused = false
        notice = nil
        busy = true
        refresh()
        commandTask?.cancel()
        commandTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.busy = false
            self?.refresh()
        }
    }
}
