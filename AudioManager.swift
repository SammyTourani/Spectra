import AVFoundation

class AudioManager: NSObject, ObservableObject {
    @Published private(set) var isPlaying: Bool = false
    private var player: AVAudioPlayer?
    private var pendingCompletion: (() -> Void)?
    
    override init() {
        super.init()
    }
    
    func playAudio(named fileName: String, completion: (() -> Void)? = nil) {
        guard let path = Bundle.main.path(forResource: fileName, ofType: "mp3") else {
            print("Could not find audio file: \(fileName)")
            return
        }
        
        let url = URL(fileURLWithPath: path)
        
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            print("Playing \(fileName)")
            
            self.isPlaying = true
            pendingCompletion = completion
            player?.play()
        } catch {
            print("Error playing audio: \(error.localizedDescription)")
            completion?()
        }
    }
    
    func stopAudio() {
        player?.stop()
        isPlaying = false
        player = nil
        pendingCompletion = nil
    }
}

extension AudioManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            print("Finished playing audio, success: \(flag)")
            if flag {
                self.pendingCompletion?()
                self.pendingCompletion = nil
            }
        }
    }
}
