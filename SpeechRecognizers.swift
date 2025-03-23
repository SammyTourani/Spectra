import Speech
import AVFoundation

class SpeechRecognizers: ObservableObject {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    
    func startRecording(_ handler: @escaping (String) -> Void) {
        guard recognizer?.isAvailable ?? false else { print("Speech recognizer unavailable"); return }
        
        // Reset previous state
        stopRecording()
        audioEngine = AVAudioEngine()
        request = SFSpeechAudioBufferRecognitionRequest()
        
        guard let audioEngine = audioEngine, let request = request else { return }
        
        let inputNode = audioEngine.inputNode
        request.shouldReportPartialResults = true
        
        recognitionTask = recognizer?.recognitionTask(with: request) { result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async { handler(text) }
            }
            if let error = error {
                print("Recognition error: \(error)")
                self.stopRecording()
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("Mic started")
        } catch {
            print("Audio engine failed: \(error)")
        }
    }
    
    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        request = nil
        recognitionTask = nil
        print("Mic stopped")
    }
}
