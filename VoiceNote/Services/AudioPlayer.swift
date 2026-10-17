import AVFoundation
import Observation

/// 저장된 녹음 파일을 재생한다.
@MainActor
@Observable
final class AudioPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var progressTask: Task<Void, Never>?

    func load(url: URL) {
        guard player == nil else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        player.play()
        isPlaying = true
        trackProgress()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        progressTask?.cancel()
    }

    func stop() {
        pause()
        seek(to: 0)
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    func skip(by seconds: TimeInterval) {
        seek(to: min(max(currentTime + seconds, 0), duration))
    }

    private func trackProgress() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    return
                }
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    // 끝까지 재생됨
                    self.isPlaying = false
                    return
                }
            }
        }
    }
}
