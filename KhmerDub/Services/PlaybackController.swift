import AVFoundation
import Combine
import Foundation

/// Plays the source media in the studio and exposes a lightweight playhead.
@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var errorMessage: String?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var durationTask: Task<Void, Never>?

    var hasItem: Bool { player?.currentItem != nil }

    func load(url: URL, durationHint: Double = 0) {
        stop()
        AudioSession.configureForPlayback()
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: item)
        player = avPlayer
        duration = max(0, durationHint)
        errorMessage = nil
        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite, seconds >= 0 {
                    self.currentTime = self.duration > 0 ? min(seconds, self.duration) : seconds
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = self.duration
            }
        }
        if durationHint <= 0 {
            durationTask?.cancel()
            durationTask = Task { [weak self] in
                do {
                    let loaded = try await asset.load(.duration)
                    guard !Task.isCancelled else { return }
                    let seconds = loaded.seconds
                    if seconds.isFinite, seconds > 0 {
                        self?.duration = seconds
                    }
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        if player.currentItem == nil { return }
        AudioSession.configureForPlayback()
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let target = seconds.clamped(to: 0...max(duration, 0.01))
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = target
    }

    func seekAndPlay(to seconds: Double) {
        seek(to: seconds)
        play()
    }

    func stop() {
        durationTask?.cancel()
        durationTask = nil
        player?.pause()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player = nil
        isPlaying = false
        currentTime = 0
    }
}

/// Plays a generated audio file, used by Voice Lab and voice test screens.
@MainActor
final class AudioFilePlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var loadedURL: URL?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var durationTask: Task<Void, Never>?

    func play(url: URL) {
        stop()
        AudioSession.configureForPlayback()
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: item)
        player = avPlayer
        loadedURL = url
        errorMessage = nil
        duration = 0
        currentTime = 0
        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite, seconds >= 0 {
                    self.currentTime = seconds
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.currentTime = self?.duration ?? 0
            }
        }
        durationTask = Task { [weak self] in
            do {
                let loaded = try await asset.load(.duration)
                guard !Task.isCancelled else { return }
                let seconds = loaded.seconds
                if seconds.isFinite, seconds > 0 {
                    self?.duration = seconds
                }
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
        isPlaying = true
        avPlayer.play()
    }

    func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            AudioSession.configureForPlayback()
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        durationTask?.cancel()
        durationTask = nil
        player?.pause()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    func reset() {
        stop()
        loadedURL = nil
        errorMessage = nil
    }
}
