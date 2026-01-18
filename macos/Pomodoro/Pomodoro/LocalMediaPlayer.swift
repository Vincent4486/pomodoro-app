//
//  LocalMediaPlayer.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LocalMediaPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTrackTitle: String = "No Track Selected"

    private let player = AVQueuePlayer()
    private var trackURLs: [URL] = []
    private var currentIndex = 0
    private var timeControlObserver: NSKeyValueObservation?
    private var currentItemObserver: NSKeyValueObservation?

    init() {
        timeControlObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.timeControlStatus == .playing
            }
        }

        currentItemObserver = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.syncCurrentTrackTitle()
            }
        }
    }

    func loadLocalFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav, .aiff]

        guard panel.runModal() == .OK else { return }
        trackURLs = panel.urls
        currentIndex = 0
        rebuildQueue(startingAt: currentIndex)
    }

    func play() {
        if player.items().isEmpty {
            rebuildQueue(startingAt: currentIndex)
        }
        player.play()
    }

    func pause() {
        player.pause()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func nextTrack() {
        guard !trackURLs.isEmpty else { return }
        let shouldPlay = isPlaying
        currentIndex = (currentIndex + 1) % trackURLs.count
        rebuildQueue(startingAt: currentIndex)
        if shouldPlay {
            player.play()
        }
    }

    func previousTrack() {
        guard !trackURLs.isEmpty else { return }
        let shouldPlay = isPlaying
        currentIndex = (currentIndex - 1 + trackURLs.count) % trackURLs.count
        rebuildQueue(startingAt: currentIndex)
        if shouldPlay {
            player.play()
        }
    }

    private func rebuildQueue(startingAt index: Int) {
        player.removeAllItems()
        guard trackURLs.indices.contains(index) else {
            currentTrackTitle = "No Track Selected"
            return
        }

        let items = trackURLs[index...].map { AVPlayerItem(url: $0) }
        for item in items {
            player.insert(item, after: nil)
        }
        syncCurrentTrackTitle()
    }

    private func syncCurrentTrackTitle() {
        guard let urlAsset = player.currentItem?.asset as? AVURLAsset else {
            currentTrackTitle = "No Track Selected"
            return
        }

        let url = urlAsset.url
        currentTrackTitle = url.deletingPathExtension().lastPathComponent
        if let index = trackURLs.firstIndex(of: url) {
            currentIndex = index
        }
    }
}
