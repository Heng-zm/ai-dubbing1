import AVFAudio
import Foundation

enum AudioSession {
    static func configure() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.allowBluetoothA2DP, .mixWithOthers]
            )
            try session.setActive(true)
        } catch {
            // Audio is still available for exports even if session activation fails.
        }
    }

    static func configureForPlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP, .mixWithOthers])
        try? session.setActive(true)
    }
}
