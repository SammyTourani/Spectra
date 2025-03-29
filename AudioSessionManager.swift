import AVFoundation

class AudioSessionManager {
    static let shared = AudioSessionManager()
    
    private var isActive = false
    
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
        guard !isActive else { return }
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            isActive = true
            print("Audio session activated")
        } catch {
            print("Error activating audio session: \(error.localizedDescription)")
        }
    }
    
    func deactivate() {
        guard isActive else { return }
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isActive = false
            print("Audio session deactivated")
        } catch {
            print("Error deactivating audio session: \(error)")
        }
    }
}
