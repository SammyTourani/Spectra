import AVFoundation

class AudioSessionManager {
    static let shared = AudioSessionManager()
    private init() {}
    
    func activate() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            print("Audio session activated")
        } catch {
            print("Error activating audio session: \(error)")
        }
    }
    
    func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("Audio session deactivated")
        } catch {
            print("Error deactivating audio session: \(error)")
        }
    }
}
