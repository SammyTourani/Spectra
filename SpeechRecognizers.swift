import Speech
import AVFoundation

class SpeechRecognizers: ObservableObject {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var isRecording = false
    
    // Add a callback for when we're ready to listen again
    func startRecording(
        onMicStateChange: @escaping (Bool) -> Void,
        onRecognition: @escaping (String) -> Void
    ) {
        // Make sure we're starting fresh
        stopRecording()
        onMicStateChange(false)
        
        // Check if recognition is available
        guard recognizer?.isAvailable ?? false else {
            print("Speech recognizer unavailable")
            return
        }
        
        // Activate the audio session for recording
        AudioSessionManager.shared.activate()
        
        audioEngine = AVAudioEngine()
        request = SFSpeechAudioBufferRecognitionRequest()
        
        guard let audioEngine = audioEngine, let request = request else {
            print("Could not create audio engine or request")
            AudioSessionManager.shared.deactivate()
            return
        }
        
        let inputNode = audioEngine.inputNode
        request.shouldReportPartialResults = true
        
        recognitionTask = recognizer?.recognitionTask(with: request) { result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    onRecognition(text)
                }
            }
            if let error = error {
                print("Recognition error: \(error)")
                DispatchQueue.main.async {
                    onMicStateChange(false)
                }
                AudioSessionManager.shared.deactivate()
            }
        }
        
        // Configure audio input
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        // Start the audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            print("Mic started")
            
            // Update the microphone state
            DispatchQueue.main.async {
                onMicStateChange(true)
            }
        } catch {
            print("Audio engine failed: \(error)")
            stopRecording()
            DispatchQueue.main.async {
                onMicStateChange(false)
            }
            AudioSessionManager.shared.deactivate()
        }
    }
    
    // Provide backward compatibility for existing code
    func startRecording(_ handler: @escaping (String) -> Void) {
        startRecording(onMicStateChange: { _ in }, onRecognition: handler)
    }
    
    func stopRecording() {
        if isRecording {
            if let audioEngine = audioEngine, audioEngine.isRunning {
                audioEngine.stop()
                audioEngine.inputNode.removeTap(onBus: 0)
                print("Mic stopped")
            }
            
            request?.endAudio()
            recognitionTask?.cancel()
            
            audioEngine = nil
            request = nil
            recognitionTask = nil
            isRecording = false
            
            AudioSessionManager.shared.deactivate()
        }
    }
    
    deinit {
        stopRecording()
    }
}
