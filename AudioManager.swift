import AVFoundation

class AudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var completion: (() -> Void)?
    
    func playAudio(named name: String, completion: @escaping () -> Void) {
        // Stop any ongoing playback
        stopAudio()
        
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else {
            print("Error: Audio file \(name).mp3 not found in bundle")
            completion()
            return
        }
        
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            self.completion = completion
            player?.prepareToPlay() // Preload audio to reduce latency
            let success = player?.play()
            if success == false {
                print("Error: Failed to start playback for \(name)")
                self.completion?()
                self.completion = nil
            } else {
                print("Playing \(name).mp3")
            }
        } catch {
            print("Error initializing player for \(name): \(error)")
            completion()
            self.completion = nil
        }
    }
    
    func stopAudio() {
        player?.stop()
        player = nil
        completion?()
        completion = nil
    }
    
    // MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("Finished playing audio, success: \(flag)")
        completion?()
        completion = nil
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("Audio decode error: \(error?.localizedDescription ?? "Unknown")")
        completion?()
        completion = nil
    }
}
