//
//  MediaControlBar.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import SwiftUI

struct MediaControlBar: View {
    @EnvironmentObject private var audioSourceStore: AudioSourceStore
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        HStack(spacing: 12) {
            if case .external(let media) = audioSourceStore.audioSource {
                artworkView(for: media)

                VStack(alignment: .leading, spacing: 4) {
                    Text(localizationManager.format("audio.now_playing_source", media.source.displayName))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(media.title)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(media.artist)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            } else {
                ZStack {
                    Circle()
                        .fill(.quaternary)
                    Image(systemName: "music.note")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(localizationManager.text("audio.none_playing"))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(localizationManager.text("audio.start_external_hint"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.2))
        )
    }

    @ViewBuilder
    private func artworkView(for media: ExternalMedia) -> some View {
        if let artwork = media.artwork {
            Image(nsImage: artwork)
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary)
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 32)
        }
    }
}

#if DEBUG && PREVIEWS_ENABLED
#Preview {
    let appState = AppState()
    let musicController = MusicController(ambientNoiseEngine: appState.ambientNoiseEngine)
    let audioSourceStore = MainActor.assumeIsolated {
        let externalMonitor = ExternalAudioMonitor()
        let externalController = ExternalPlaybackController()
        AudioSourceStore(
            musicController: musicController,
            externalMonitor: externalMonitor,
            externalController: externalController
        )
    }
    MediaControlBar()
        .environmentObject(audioSourceStore)
        .padding()
}
#endif
