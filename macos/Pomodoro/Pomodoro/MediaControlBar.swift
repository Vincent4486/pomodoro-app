//
//  MediaControlBar.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import SwiftUI

struct MediaControlBar: View {
    @EnvironmentObject private var mediaPlayer: LocalMediaPlayer

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.quaternary)
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(mediaPlayer.currentTrackTitle)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Button("Choose Music") {
                    mediaPlayer.loadLocalFiles()
                }
                .buttonStyle(.link)
                .font(.system(.caption, design: .rounded))
            }

            Spacer(minLength: 8)

            Button {
                mediaPlayer.togglePlayPause()
            } label: {
                Image(systemName: mediaPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .background(Circle().fill(.ultraThinMaterial))

            Button {
                mediaPlayer.nextTrack()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .background(Circle().fill(.ultraThinMaterial))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.2))
        )
    }
}

#Preview {
    MediaControlBar()
        .environmentObject(LocalMediaPlayer())
        .padding()
}
