import SwiftUI
import UIKit
import AVFAudio
import EonaCore
import EonaData

/// Backend diagnostic (admin): the backend address, the GPS fix, and a check of each endpoint.
struct DiagnosticScreen: View {
    let services: AppServices

    @State private var running = false
    @State private var results: [CheckResult] = []
    /// Lecteur système : relevé brut d'iOS et essais de commandes, variante interne seulement.
    @State private var mediaReport: String?
    @State private var mediaLog: [String] = []
    @State private var mediaReading = false
    /// Sondes publiques Apple (systemMusicPlayer, session audio), tous lecteurs.
    @State private var publicProbe = PublicMediaProbe()

    var body: some View {
        Form {
            Section("Adresse du backend") {
                Text(BackendDiagnostics(client: services.client).baseURL.absoluteString)
                    .font(.xrFootnote.monospaced())
                    .foregroundStyle(EonaColor.textSecondary)
                    .textSelection(.enabled)
            }

            Section("GPS") {
                Text(gpsText)
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textSecondary)
            }

            if EONASystemMedia.isEnabled() {
                Section {
                    Text(mediaReport ?? "Lance un titre dans l'autre app, reviens ici, puis Relever.")
                        .font(.xrFootnote.monospaced())
                        .foregroundStyle(EonaColor.textSecondary)
                        .textSelection(.enabled)
                    Button(mediaReading ? "Relevé en cours…" : "Relever") { readMedia() }
                        .disabled(mediaReading)
                    ForEach(MediaProbe.all) { probe in
                        Button(probe.title) { send(probe) }
                    }
                    ForEach(Array(mediaLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.xrFootnote.monospaced())
                            .foregroundStyle(EonaColor.textSecondary)
                    }
                    Button("Copier le relevé") {
                        UIPasteboard.general.string = ([mediaReport ?? "Aucun relevé"] + mediaLog).joined(separator: "\n")
                    }
                } header: {
                    Text("Lecteur système")
                } footer: {
                    Text("Données brutes d'iOS, rien d'interprété. Essais : écoute l'effet dans l'autre app.")
                }
            }

            Section {
                Text(publicProbe.report ?? "Lance un titre dans n'importe quelle app (Spotify, YouTube, Deezer…), reviens ici, puis Lire.")
                    .font(.xrFootnote.monospaced())
                    .foregroundStyle(EonaColor.textSecondary)
                    .textSelection(.enabled)
                Button("Lire") { Task { await publicProbe.read() } }
                ForEach(PublicMediaProbe.Command.allCases) { command in
                    Button(command.title) { publicProbe.send(command) }
                }
                ForEach(Array(publicProbe.log.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.xrFootnote.monospaced())
                        .foregroundStyle(EonaColor.textSecondary)
                }
                Button("Copier") { UIPasteboard.general.string = publicProbe.copyText }
            } header: {
                Text("Sondes publiques Apple")
            } footer: {
                Text("systemMusicPlayer et session audio. Journal : changements vus écran ouvert, change de titre dans l'autre app pour tester.")
            }

            Section {
                EonaButton(title: running ? "Test en cours…" : "Relancer le test", loading: running, fillWidth: true) {
                    Task { await runChecks() }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            ForEach(results, id: \.name) { result in
                Section {
                    VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                        HStack(spacing: EonaSpacing.sm) {
                            Image(result.ok ? EonaSymbol.check : EonaSymbol.close)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(result.ok ? EonaColor.success : EonaColor.danger)
                            Text(result.name)
                                .font(.xrHeadline)
                                .foregroundStyle(EonaColor.textPrimary)
                        }
                        Text(result.detail)
                            .font(.xrFootnote)
                            .foregroundStyle(EonaColor.textSecondary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(EonaColor.canvas)
        .navigationTitle("Diagnostic backend")
        .task { await runChecks() }
        .onAppear { publicProbe.start() }
        .onDisappear { publicProbe.stop() }
    }

    private func readMedia() {
        mediaReading = true
        EONASystemMedia.diagnose { report in
            MainActor.assumeIsolated {
                let otherAudio = AVAudioSession.sharedInstance().isOtherAudioPlaying ? "oui" : "non"
                mediaReport = report + "\nAutre audio actif (AVAudioSession) : " + otherAudio
                mediaReading = false
            }
        }
    }

    private func send(_ probe: MediaProbe) {
        EONASystemMedia.probe(probe.command, interval: probe.interval.map { NSNumber(value: $0) }, viaApp: probe.viaApp) { result in
            MainActor.assumeIsolated {
                mediaLog.insert(result, at: 0)
                if mediaLog.count > 12 { mediaLog.removeLast() }
            }
        }
    }

    private func runChecks() async {
        guard !running else { return }
        running = true
        results = await BackendDiagnostics(client: services.client).run()
        running = false
    }

    private var gpsText: String {
        let signal: String = switch services.location.signal {
        case .searching: "recherche"
        case .good: "bon"
        case .weak: "faible"
        case .lost: "perdu"
        }
        guard let fix = services.location.location else {
            return "Pas encore de position (\(signal)) — sans fix GPS, l'app ne charge pas les radars."
        }
        return "Fix OK (\(signal)) — \(String(format: "%.5f", fix.latitude)), \(String(format: "%.5f", fix.longitude))"
    }
}

/// Un essai de commande : transport legacy (celui de Lecture/Pause) ou envoi ciblé.
private struct MediaProbe: Identifiable {
    let title: String
    let command: EONASystemMediaCommand
    let interval: Double?
    let viaApp: Bool

    var id: String { title }

    static var all: [MediaProbe] {
        [
            MediaProbe(title: "Suivant · legacy", command: .next, interval: nil, viaApp: false),
            MediaProbe(title: "Précédent · legacy", command: .previous, interval: nil, viaApp: false),
            MediaProbe(title: "Avance 15 s · legacy", command: .skipForward, interval: 15, viaApp: false),
            MediaProbe(title: "Recul 15 s · legacy", command: .skipBackward, interval: 15, viaApp: false),
            MediaProbe(title: "Suivant · ciblé", command: .next, interval: nil, viaApp: true),
            MediaProbe(title: "Avance 15 s · ciblé", command: .skipForward, interval: 15, viaApp: true),
        ]
    }
}
