import Foundation
import AVFoundation
import SwiftUI

class AudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    
    @Published var isPlaying = false
    
    private var player: AVAudioPlayer?
    private var pendingCompletion: (() -> Void)?
    
    override init() {
        super.init()
    }
    
    func playAudio(named fileName: String, completion: (() -> Void)? = nil) {
        guard let path = Bundle.main.path(forResource: fileName, ofType: "mp3") else {
            print("Could not find audio file: \(fileName)")
            completion?()
            return
        }
        
        let url = URL(fileURLWithPath: path)
        
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            print("Playing \(fileName)")
            
            // Make sure audio session is active before playing
            AudioSessionManager.shared.activate()
            
            // Mark that audio playback is starting
            AudioSessionManager.shared.markAudioPlaybackStarted()
            
            self.isPlaying = true
            pendingCompletion = completion
            
            // Set volume to full for voice instructions
            player?.volume = 1.0
            player?.play()
        } catch {
            print("Error playing audio: \(error.localizedDescription)")
            completion?()
        }
    }
    
    func stopAudio() {
        if let player = player, player.isPlaying {
            player.stop()
            self.isPlaying = false
            
            // Mark that audio playback has ended
            AudioSessionManager.shared.markAudioPlaybackEnded()
            
            // Call any pending completion handler
            if let completion = pendingCompletion {
                DispatchQueue.main.async {
                    completion()
                }
                pendingCompletion = nil
            }
        }
    }
    
    // AVAudioPlayerDelegate methods
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("Finished playing audio, success: \(flag)")
        
        // Mark that audio playback has ended
        AudioSessionManager.shared.markAudioPlaybackEnded()
        
        DispatchQueue.main.async {
            self.isPlaying = false
            if let completion = self.pendingCompletion {
                completion()
                self.pendingCompletion = nil
            }
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("Audio player decode error: \(error?.localizedDescription ?? "unknown error")")
        
        // Mark that audio playback has ended even though it failed
        AudioSessionManager.shared.markAudioPlaybackEnded()
        
        DispatchQueue.main.async {
            self.isPlaying = false
            if let completion = self.pendingCompletion {
                completion()
                self.pendingCompletion = nil
            }
        }
    }
    
    // Clean up when the manager is deallocated
    deinit {
        stopAudio()
        print("AudioManager: Deinitialized")
    }
}
