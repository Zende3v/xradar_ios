import SwiftUI
import UIKit

/// Compact mini-player under the search bar: the track in Music with previous, play-pause and
/// next. With nothing loaded the player stays, and play starts Music. Every control is at least
/// 48 pt, for a thumb while driving.
struct MusicBanner: View {
    let player: MusicPlayer

    private static let controlSize: CGFloat = 48

    var body: some View {
        Group {
            switch player.playback {
            case .active(let title, let artist, let artwork, let isPlaying):
                controls(title: title ?? "Apple Music", subtitle: artist ?? "Apple Music", artwork: artwork, isPlaying: isPlaying)
            case .idle:
                controls(title: "Appuie sur lecture", subtitle: "Apple Music", artwork: nil, isPlaying: false)
            case .permissionMissing(let canAsk):
                accessMissing(canAsk: canAsk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: EonaRadius.lg))
    }

    private func controls(title: String, subtitle: String, artwork: UIImage?, isPlaying: Bool) -> some View {
        HStack(spacing: EonaSpacing.sm) {
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

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.xrHeadline)
                    .foregroundStyle(EonaColor.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: EonaSpacing.xs) {
                EonaIconButton(icon: .symbol(.musicPrevious), label: "Titre précédent", size: Self.controlSize, glass: false) {
                    player.previous()
                }
                EonaIconButton(icon: .symbol(isPlaying ? .pause : .play), label: isPlaying ? "Pause" : "Lecture", size: Self.controlSize, glass: false) {
                    player.playPause()
                }
                EonaIconButton(icon: .symbol(.musicNext), label: "Titre suivant", size: Self.controlSize, glass: false) {
                    player.next()
                }
            }
        }
        .padding(EonaSpacing.sm)
    }

    /// Access to Music not given: one line, and the way to give it.
    private func accessMissing(canAsk: Bool) -> some View {
        HStack(spacing: EonaSpacing.md) {
            EonaIconView(icon: .symbol(.music), size: 24)
                .foregroundStyle(EonaColor.textSecondary)
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
        .padding(EonaSpacing.md)
    }
}
