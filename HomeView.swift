import SwiftUI
import AVFoundation

struct HomeView: View {
    @ObservedObject private var speechRecognizers = SpeechRecognizers()
    private let cameraManager = CameraManager()
    private let apiService = APIService.shared
    
    @State private var isListening = false
    @State private var isSpeaking = false
    @State private var finalRecognizedText = ""
    @State private var serverResponseText = ""
    @State private var buttonStatusText = "Awaiting command"
    @State private var isProcessingImage = false
    @State private var errorMessage: String? = nil
    @State private var shouldCaptureImages = false
    
    var body: some View {
        ZStack {
            Color(red: 175/255, green: 196/255, blue: 214/255)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                Text("Spectra")
                    .font(.largeTitle)
                    .foregroundColor(.black)
                    .padding(.bottom, 20)
                
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .background(Circle().fill(isSpeaking ? Color.green : Color.blue))
                    .frame(width: 100, height: 100)
                    .scaleEffect(isSpeaking ? 1.4 : 1.0)
                    .animation(
                        isSpeaking ? Animation.easeInOut(duration: 0.75).repeatForever(autoreverses: true) : .default,
                        value: isSpeaking
                    )
                    .onTapGesture {
                        handleTapGesture()
                    }
                
                Text(buttonStatusText)
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .padding(.top, 30)
                
                Spacer()
                
                VStack {
                    Text(serverResponseText.isEmpty ? "Response will appear here" : serverResponseText)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
            
            if isProcessingImage {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                
                ProgressView("Processing...")
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.7)))
            }
        }
        .onAppear {
            prepareAudioSession()
        }
        .onDisappear {
            stopImageCapturing()
        }
    }
    
    private func prepareAudioSession() {
        AudioSessionManager.shared.activate()
    }
    
    private func handleTapGesture() {
        isListening.toggle()
        
        if isListening {
            startListening()
        } else {
            stopListening()
        }
    }
    
    private func startListening() {
        buttonStatusText = "Listening..."
        finalRecognizedText = ""
        serverResponseText = ""
        errorMessage = nil
        shouldCaptureImages = false
        
        speechRecognizers.startRecording { recognizedText in
            finalRecognizedText = recognizedText
            isSpeaking = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isSpeaking = false
            }
        }
    }
    
    private func stopListening() {
        buttonStatusText = "Processing request"
        speechRecognizers.stopRecording()
        if !finalRecognizedText.isEmpty {
            sendRecognizedTextToServer(finalRecognizedText)
        } else {
            buttonStatusText = "No speech detected"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                buttonStatusText = "Awaiting command"
            }
        }
    }
    
    private func sendRecognizedTextToServer(_ recognizedText: String) {
        apiService.sendSpeechCommand(recognizedText) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    serverResponseText = response
                    buttonStatusText = "Command received"
                    
                    // Check if we should start capturing images based on the response
                    if response.contains("point your camera") ||
                       response.contains("describe what is") ||
                       response.contains("locating the object") {
                        startImageCapturing()
                    }
                    
                case .failure(let error):
                    errorMessage = "Failed to send command: \(error.localizedDescription)"
                    buttonStatusText = "Command failed"
                }
            }
        }
    }
    
    private func startImageCapturing() {
        stopImageCapturing() // Ensure we stop any existing capture
        
        shouldCaptureImages = true
        isProcessingImage = true
        
        cameraManager.startCapturingFrames { capturedImage in
            guard shouldCaptureImages else { return }
            
            // Only process one image at a time
            if isProcessingImage {
                processImage(capturedImage)
            }
        }
    }
    
    private func processImage(_ image: UIImage) {
        apiService.sendImage(image) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    serverResponseText = response.text
                    
                    // Play audio if available
                    if let audioData = response.audioData {
                        apiService.playAudioData(audioData)
                    }
                    
                    // Give time for user to process before capturing next image
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        // Only continue if we're still in image capturing mode
                        if shouldCaptureImages {
                            isProcessingImage = true
                        }
                    }
                    
                case .failure(let error):
                    errorMessage = "Image processing error: \(error.localizedDescription)"
                    
                    // Retry after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        if shouldCaptureImages {
                            isProcessingImage = true
                        }
                    }
                }
                
                // Mark as not processing until next cycle
                isProcessingImage = false
            }
        }
    }
    
    private func stopImageCapturing() {
        shouldCaptureImages = false
        isProcessingImage = false
        cameraManager.stop()
    }
}
