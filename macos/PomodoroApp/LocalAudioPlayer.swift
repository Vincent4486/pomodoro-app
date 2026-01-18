import AVFoundation

@MainActor
final class LocalAudioPlayer: NSObject, ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    private var currentResource: String?
    private var currentExtension: String?

    override init() {
        super.init()
        configureAudioSession()
    }

    func playBundledAudio(named resource: String, withExtension fileExtension: String, loop: Bool = false) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: fileExtension) else {
            print("LocalAudioPlayer: Missing bundled audio file \(resource).\(fileExtension)")
            return
        }

        if audioPlayer == nil || currentResource != resource || currentExtension != fileExtension {
            loadPlayer(url: url, loop: loop)
        } else {
            audioPlayer?.numberOfLoops = loop ? -1 : 0
        }

        audioPlayer?.play()
    }

    func pause() {
        audioPlayer?.pause()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
    }

    private func loadPlayer(url: URL, loop: Bool) {
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 1.0
            player.numberOfLoops = loop ? -1 : 0
            player.prepareToPlay()
            audioPlayer = player
            currentResource = url.deletingPathExtension().lastPathComponent
            currentExtension = url.pathExtension
        } catch {
            audioPlayer = nil
            print("LocalAudioPlayer: Failed to load audio: \(error.localizedDescription)")
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("LocalAudioPlayer: Failed to configure audio session: \(error.localizedDescription)")
        }
    }
}
