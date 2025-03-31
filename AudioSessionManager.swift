import AVFoundation
import Foundation

class AudioSessionManager {
    static let shared = AudioSessionManager()
    
    private var queue = DispatchQueue(label: "com.spectra.audioSessionManager", qos: .userInitiated)
    private var isAudioSessionActive = false
    private var isPlayingAudio = false
    private var activationCount = 0
    
    private var currentCategory: AVAudioSession.Category = .playAndRecord // Changed default to .playAndRecord
    private var currentMode: AVAudioSession.Mode = .default
    
    private init() {
        setupNotifications()
    }
    
    func configure(category: AVAudioSession.Category, mode: AVAudioSession.Mode) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            if self.currentCategory != category || self.currentMode != mode {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(category, options: [.defaultToSpeaker, .allowBluetooth])
                    try session.setMode(mode)
                    
                    self.currentCategory = category
                    self.currentMode = mode
                    print("Audio session configured with category: \(category), mode: \(mode)")
                } catch {
                    print("Failed to configure audio session: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func activate() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            self.activationCount += 1
            
            if !self.isAudioSessionActive {
                do {
                    let session = AVAudioSession.sharedInstance()
                    // Ensure .defaultToSpeaker is always set
                    try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
                    try session.setMode(.default)
                    try session.setActive(true)
                    self.isAudioSessionActive = true
                    self.currentCategory = .playAndRecord
                    self.currentMode = .default
                    print("Audio session activated")
                } catch {
                    print("Failed to activate audio session: \(error.localizedDescription)")
                }
            } else {
                print("Audio session already active, skipping activation")
            }
        }
    }
    
    func deactivate() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            if self.activationCount > 0 {
                self.activationCount -= 1
            }
            
            if self.activationCount == 0 && !self.isPlayingAudio {
                do {
                    try AVAudioSession.sharedInstance().setActive(false)
                    self.isAudioSessionActive = false
                    print("Audio session deactivated")
                } catch {
                    print("Error deactivating audio session (ignorable): \(error)")
                }
            } else if self.isPlayingAudio {
                print("Audio playback in progress, deferring session deactivation")
            } else {
                print("Audio session still needed, skipping deactivation")
            }
        }
    }
    
    func markAudioPlaybackStarted() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isPlayingAudio = true
        }
    }
    
    func markAudioPlaybackEnded() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isPlayingAudio = false
            
            if self.activationCount == 0 && self.isAudioSessionActive {
                do {
                    try AVAudioSession.sharedInstance().setActive(false)
                    self.isAudioSessionActive = false
                    print("Audio session deactivated after playback")
                } catch {
                    print("Error deactivating audio session: \(error)")
                }
            }
        }
    }
    
    func resetAndActivate() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            self.activationCount = 1
            
            do {
                if self.isAudioSessionActive {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
                
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
                try AVAudioSession.sharedInstance().setMode(.default)
                try AVAudioSession.sharedInstance().setActive(true)
                
                self.isAudioSessionActive = true
                self.currentCategory = .playAndRecord
                self.currentMode = .default
                
                print("Audio session reset and activated")
            } catch {
                print("Failed to reset audio session: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            print("Audio interruption began")
            queue.async { [weak self] in
                self?.isAudioSessionActive = false
            }
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                print("Audio interruption ended - resuming")
                activate()
            } else {
                print("Audio interruption ended - not resuming")
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .newDeviceAvailable:
            print("Audio route changed: new device available")
        case .oldDeviceUnavailable:
            print("Audio route changed: old device unavailable")
        default:
            break
        }
    }
    
    @objc private func handleMediaServicesReset(notification: Notification) {
        print("Media services were reset")
        resetAndActivate()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
