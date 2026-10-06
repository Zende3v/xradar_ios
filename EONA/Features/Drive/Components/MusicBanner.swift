import SwiftUI
import UIKit

/// Mini-player compact. Sources disponibles via pochette ; commandes de 48 pt.
struct MusicBanner: View {
    let player: MusicPlayer

    private static let controlSize: CGFloat = 48
    /// Spotify's own green, for its name only.
    private static let spotifyGreen = Color(red: 0x1D / 255.0, green: 0xB9 / 255.0, blue: 0x54 / 255.0)

    var body: some View {
        Group {
            switch player.playback {
            case .active(let title, let artist, let artwork, let isPlaying):
                controls(title: title ?? player.source.name, subtitle: artist ?? player.source.name, artwork: artwork, isPlaying: isPlaying)
            case .systemControls(let title, let artist, let artwork, let isPlaying):
                controls(
                    title: title ?? "Lecteur système",
                    subtitle: artist ?? "Lecture depuis ton app",
                    artwork: artwork,
                    isPlaying: isPlaying
                )
            case .idle:
                if player.source == .system {
                    systemIdle
                } else {
                    controls(
                        title: "Appuie sur lecture",
                        subtitle: player.source == .spotify ? "Spotify — rien en cours" : player.source.name,
                        artwork: nil,
                        isPlaying: false
                    )
                }
            case .permissionMissing(let canAsk):
                accessMissing(canAsk: canAsk)
            case .spotifySignIn(let message):
                spotifySignIn(message: message)
            case .unavailable(let reason):
                unavailable(reason)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: EonaRadius.lg))
        .animation(.smooth(duration: 0.3), value: player.source)
    }

    private func controls(title: String, subtitle: String, artwork: UIImage?, isPlaying: Bool?) -> some View {
        HStack(spacing: EonaSpacing.sm) {
            sourceMenu {
                cover(artwork)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.xrHeadline)
                    .foregroundStyle(EonaColor.textPrimary)
                    .lineLimit(1)
                if let notice = playbackNotice {
                    Text(notice)
                        .font(.xrFootnote)
                        .foregroundStyle(EonaColor.warning)
                        .lineLimit(2)
                } else {
                    HStack(spacing: EonaSpacing.xs) {
                        if player.source == .spotify {
                            Circle().fill(Self.spotifyGreen).frame(width: 6, height: 6)
                        }
                        Text(subtitle)
                            .font(.xrFootnote)
                            .foregroundStyle(EonaColor.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: EonaSpacing.xs) {
                EonaIconButton(icon: .symbol(.musicPrevious), label: "Titre précédent", size: Self.controlSize, glass: false) {
                    player.previous()
                }
                EonaIconButton(
                    icon: .symbol(playbackSymbol(isPlaying)),
                    label: isPlaying.map { $0 ? "Pause" : "Lecture" } ?? "Lecture / pause",
                    size: Self.controlSize,
                    glass: false
                ) {
                    player.playPause()
                }
                EonaIconButton(icon: .symbol(.musicNext), label: "Titre suivant", size: Self.controlSize, glass: false) {
                    player.next()
                }
            }
            .disabled(player.source == .system && player.system.busy)
        }
        .padding(EonaSpacing.sm)
    }

    private func playbackSymbol(_ isPlaying: Bool?) -> EonaSymbol {
        switch isPlaying {
        case .some(true): .pause
        case .some(false): .play
        case nil: .playPause
        }
    }

    /// The cover, or the music note while there is none.
    private func cover(_ artwork: UIImage?) -> some View {
        Group {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                EonaIconView(icon: .symbol(.music), size: 24)
                    .foregroundStyle(EonaColor.textTertiary)
            }
        }
        .frame(width: 48, height: 48)
        .background(EonaColor.surfaceHigh)
        .clipShape(.rect(cornerRadius: EonaRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: EonaRadius.sm).strokeBorder(EonaColor.border, lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            // The way to the source menu, drawn small on the cover.
            if player.availableSources.count > 1 {
                Image(EonaSymbol.chevronDown)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(EonaColor.textPrimary)
                    .frame(width: 16, height: 16)
                    .background(EonaColor.surfaceHigh, in: .circle)
                    .offset(x: 4, y: 4)
            }
        }
        .accessibilityLabel("Source : \(player.source.name)")
    }

    /// Sources disponibles. Déconnexion Spotify conservée.
    @ViewBuilder
    private func sourceMenu<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        if player.availableSources.count > 1 {
            Menu {
                Picker("Source", selection: Binding(get: { player.source }, set: { player.choose($0) })) {
                    ForEach(player.availableSources, id: \.self) { source in
                        Text(source.name).tag(source)
                    }
                }
                if player.source == .spotify, player.spotify.isSignedIn {
                    Button("Déconnecter Spotify", role: .destructive) {
                        player.spotify.signOut()
                    }
                }
            } label: {
                label()
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        } else {
            label()
        }
    }

    /// Access to Music not given: one line, and the way to give it — or to switch to Spotify.
    private func accessMissing(canAsk: Bool) -> some View {
        HStack(spacing: EonaSpacing.md) {
            sourceMenu {
                cover(nil)
            }
            Text("Autoriser l'accès à Musique")
                .font(.xrSubhead)
                .foregroundStyle(EonaColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            EonaButton(title: canAsk ? "Autoriser" : "Réglages") {
                if canAsk {
                    player.open()
                } else {
                    player.openSettings()
                }
            }
        }
        .padding(EonaSpacing.sm)
    }

    /// Spotify chosen, not connected: its sign-in page is one tap away.
    private func spotifySignIn(message: String?) -> some View {
        HStack(spacing: EonaSpacing.md) {
            sourceMenu {
                cover(nil)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: EonaSpacing.xs) {
                    Circle().fill(Self.spotifyGreen).frame(width: 6, height: 6)
                    Text("Spotify")
                        .font(.xrSubhead.weight(.semibold))
                        .foregroundStyle(EonaColor.textPrimary)
                }
                Text(message ?? "Connecte ton compte pour piloter ta musique.")
                    .font(.xrFootnote)
                    .foregroundStyle(message == nil ? EonaColor.textSecondary : EonaColor.warning)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            EonaButton(title: "Connecter", loading: player.spotify.busy) {
                Task { await player.spotify.signIn() }
            }
        }
        .padding(EonaSpacing.sm)
    }

    private var playbackNotice: String? {
        switch player.source {
        case .appleMusic: nil
        case .spotify: player.spotify.notice
        case .system: player.system.notice
        }
    }

    private var systemIdle: some View {
        HStack(spacing: EonaSpacing.md) {
            sourceMenu {
                cover(nil)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Lance une lecture dans ton app")
                    .font(.xrSubhead)
                    .foregroundStyle(EonaColor.textPrimary)
                    .lineLimit(2)
                Text(player.system.notice ?? player.source.name)
                    .font(.xrFootnote)
                    .foregroundStyle(player.system.notice == nil ? EonaColor.textSecondary : EonaColor.warning)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EonaSpacing.sm)
    }

    /// Source indisponible : raison visible, changement de source toujours accessible.
    private func unavailable(_ reason: String) -> some View {
        HStack(spacing: EonaSpacing.md) {
            sourceMenu {
                cover(nil)
            }
            Text(reason)
                .font(.xrFootnote)
                .foregroundStyle(EonaColor.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if player.source == .system {
                EonaButton(title: "Réessayer", loading: player.system.busy) {
                    player.retrySystem()
                }
            }
        }
        .padding(EonaSpacing.sm)
    }
}
