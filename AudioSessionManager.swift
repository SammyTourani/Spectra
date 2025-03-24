import AVFoundation

class AudioSessionManager {
    static let shared = AudioSessionManager()
    
    private init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setMode(.default)
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
    }
    
    func activate() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            print("Audio session activated")
        } catch {
            print("Error activating audio session: \(error.localizedDescription)")
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
