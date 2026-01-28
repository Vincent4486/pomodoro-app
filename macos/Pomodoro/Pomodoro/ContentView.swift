//
//  ContentView.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var onboardingState: OnboardingState

    var body: some View {
        MainWindowView()
            .sheet(isPresented: $onboardingState.isPresented, onDismiss: {
                onboardingState.markCompleted()
            }) {
                OnboardingFlowView()
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
    ContentView()
        .environmentObject(appState)
        .environmentObject(musicController)
        .environmentObject(audioSourceStore)
        .environmentObject(OnboardingState())
}
#endif
