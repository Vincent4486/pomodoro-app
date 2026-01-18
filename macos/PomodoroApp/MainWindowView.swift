import SwiftUI

struct MainWindowView: View {
    @StateObject private var audioPlayer = LocalAudioPlayer()

    var body: some View {
        VStack(spacing: 12) {
            Text("Pomodoro")
                .font(.largeTitle)
            Text("Ready to focus.")
                .foregroundStyle(.secondary)
            Button("▶ Play Test Sound") {
                audioPlayer.playBundledAudio(named: "test_music", withExtension: "wav")
            }
            .buttonStyle(.borderedProminent)
            DebugStateView()
        }
        .frame(minWidth: 480, minHeight: 320)
        .padding(32)
    }
}

#Preview {
    MainWindowView()
        .environmentObject(AppState())
}
