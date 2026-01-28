//
//  PomodoroApp.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import SwiftUI

@MainActor
@main
struct PomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState
    @StateObject private var musicController: MusicController
    @StateObject private var audioSourceStore: AudioSourceStore
    @StateObject private var onboardingState: OnboardingState

    init() {
        let appState = AppState()
        let musicController = MusicController(ambientNoiseEngine: appState.ambientNoiseEngine)
        let externalMonitor = ExternalAudioMonitor()
        let externalController = ExternalPlaybackController()
        _appState = StateObject(wrappedValue: appState)
        _musicController = StateObject(wrappedValue: musicController)
        _audioSourceStore = StateObject(
            wrappedValue: AudioSourceStore(
                musicController: musicController,
                externalMonitor: externalMonitor,
                externalController: externalController
            )
        )
        _onboardingState = StateObject(wrappedValue: OnboardingState())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(musicController)
                .environmentObject(audioSourceStore)
                .environmentObject(onboardingState)
                .task(id: ObjectIdentifier(appState)) {
                    appDelegate.appState = appState
                    appDelegate.musicController = musicController
                    appDelegate.audioSourceStore = audioSourceStore
                    appDelegate.onboardingState = onboardingState
                }
        }
        .commands {
            CommandMenu("Timer") {
                Button("Start/Pause Pomodoro") {
                    // Spacebar should be inert while in Flow Mode to keep the focus surface passive.
                    guard !appState.isInFlowMode else { return }
                    appState.startOrPausePomodoro()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Reset Pomodoro") {
                    appState.resetPomodoro()
                }
                .keyboardShortcut("r", modifiers: [])

                Divider()

                Button("Start Countdown") {
                    appState.startCountdown()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(appState.countdown.state != .idle)
            }
        }
    }
}
