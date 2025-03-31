import AVFoundation

class AudioSessionManager {
    static let shared = AudioSessionManager()
    
    private var isActive = false
    private let queue = DispatchQueue(label: "com.spectra.audiosession")
    private var deactivationTimer: Timer?
    
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
        queue.async { [weak self] in
            guard let self = self, !self.isActive else { return }
            
            // Cancel any pending deactivation
            self.deactivationTimer?.invalidate()
            self.deactivationTimer = nil
            
            do {
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                DispatchQueue.main.async {
                    self.isActive = true
                    print("Audio session activated")
                }
            } catch {
                print("Error activating audio session: \(error.localizedDescription)")
            }
        }
    }
    
    func deactivate() {
        queue.async { [weak self] in
            guard let self = self, self.isActive else { return }
            
            // Cancel any existing deactivation timer
            self.deactivationTimer?.invalidate()
            
            // Create a new timer for deactivation
            self.deactivationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                
                do {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    DispatchQueue.main.async {
                        self.isActive = false
                        print("Audio session deactivated")
                    }
                } catch {
                    print("Error deactivating audio session: \(error)")
                    // If deactivation fails, try to reset the session
                    self.resetSession()
                }
            }
        }
    }
    
    private func resetSession() {
        queue.async {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setActive(false, options: .notifyOthersOnDeactivation)
                try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
                try session.setMode(.default)
                self.isActive = false
                print("Audio session reset successful")
            } catch {
                print("Failed to reset audio session: \(error.localizedDescription)")
            }
        }
    }
    
    func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Audio session was interrupted, update state accordingly
            DispatchQueue.main.async {
                self.isActive = false
            }
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // Interruption ended, reactivate if needed
                activate()
            }
        @unknown default:
            break
        }
    }
}
