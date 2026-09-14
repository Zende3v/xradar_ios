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
        .glassEffect(.regular, in: .rect(cornerRadius: XRadarRadius.lg))
    }

    private func controls(title: String, subtitle: String, artwork: UIImage?, isPlaying: Bool) -> some View {
        HStack(spacing: XRadarSpacing.sm) {
            Group {
                if let artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                } else {
                    XRadarIconView(icon: .symbol(.music), size: 24)
                        .foregroundStyle(XRadarColor.textTertiary)
                }
            }
            .frame(width: 48, height: 48)
            .background(XRadarColor.surfaceHigh)
            .clipShape(.rect(cornerRadius: XRadarRadius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: XRadarRadius.sm).strokeBorder(XRadarColor.border, lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.xrHeadline)
                    .foregroundStyle(XRadarColor.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.xrFootnote)
                    .foregroundStyle(XRadarColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: XRadarSpacing.xs) {
                XRadarIconButton(icon: .symbol(.musicPrevious), label: "Titre précédent", size: Self.controlSize, glass: false) {
                    player.previous()
                }
                XRadarIconButton(icon: .symbol(isPlaying ? .pause : .play), label: isPlaying ? "Pause" : "Lecture", size: Self.controlSize, glass: false) {
                    player.playPause()
                }
                XRadarIconButton(icon: .symbol(.musicNext), label: "Titre suivant", size: Self.controlSize, glass: false) {
                    player.next()
                }
            }
        }
        .padding(XRadarSpacing.sm)
    }

    /// Access to Music not given: one line, and the way to give it.
    private func accessMissing(canAsk: Bool) -> some View {
        HStack(spacing: XRadarSpacing.md) {
            XRadarIconView(icon: .symbol(.music), size: 24)
                .foregroundStyle(XRadarColor.textSecondary)
            Text("Autoriser l'accès à Musique")
                .font(.xrSubhead)
                .foregroundStyle(XRadarColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            XRadarButton(title: canAsk ? "Autoriser" : "Réglages") {
                if canAsk {
                    player.open()
                } else {
                    player.openSettings()
                }
            }
        }
        .padding(XRadarSpacing.md)
    }
}
