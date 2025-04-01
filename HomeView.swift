import SwiftUI
import AVFoundation

struct HomeView: View {
    // MARK: - Properties
    @ObservedObject private var speechRecognizers = SpeechRecognizers()
    private let cameraManager = CameraManager()
    private let apiService = APIService.shared
    
    // MARK: - State Properties
    @State private var isListening = false
    @State private var isSpeaking = false
    @State private var finalRecognizedText = ""
    @State private var serverResponseText = ""
    @State private var buttonStatusText = "Awaiting command"
    @State private var isProcessingImage = false
    @State private var errorMessage: String? = nil
    @State private var shouldCaptureImages = false
    
    // MARK: - Animation Properties
    @State private var pulseAnimation = false
    @State private var gradientRotation = 0.0
    @State private var responseOpacity = 0.0
    @State private var titleScale = 1.0
    @State private var buttonScale = 1.0
    @State private var buttonRotation = 0.0
    @State private var appearingElements = false
    
    // MARK: - Computed Properties
    private var buttonGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: isSpeaking ?
                             [Color.green.opacity(0.7), Color.blue.opacity(0.9)] :
                             [Color.blue.opacity(0.7), Color.purple.opacity(0.9)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundView
                
                VStack(spacing: 25) {
                    titleView
                        .padding(.top, geometry.size.height * 0.05)
                    
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .fill(buttonGradient)
                            .frame(width: 110, height: 110)
                            .shadow(color: isSpeaking ? .green.opacity(0.5) : .blue.opacity(0.5),
                                   radius: pulseAnimation ? 20 : 10, x: 0, y: 0)
                            .scaleEffect(pulseAnimation ? 1.1 : 0.95)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                      value: pulseAnimation)
                        
                        Circle()
                            .stroke(Color.white.opacity(0.7), lineWidth: 4)
                            .frame(width: 100, height: 100)
                            .overlay(
                                Circle()
                                    .trim(from: 0, to: isListening ? 0.75 : 0.0)
                                    .stroke(Color.white, lineWidth: 4)
                                    .rotationEffect(.degrees(gradientRotation))
                                    .animation(isListening ?
                                              .linear(duration: 2).repeatForever(autoreverses: false) :
                                              .default, value: isListening)
                            )
                        
                        Image(systemName: isListening ? "waveform" : "mic.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(buttonScale)
                            .rotationEffect(.degrees(buttonRotation))
                    }
                    .frame(width: 110, height: 110)
                    .scaleEffect(isSpeaking ? 1.2 : 1.0)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            .blur(radius: 3)
                            .scaleEffect(1.1)
                            .opacity(isSpeaking ? 1 : 0)
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            buttonScale = 0.9
                            buttonRotation = isListening ? 0 : 180
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                buttonScale = 1
                            }
                            handleTapGesture()
                        }
                    }
                    
                    statusView
                        .padding(.top, 15)
                    
                    Spacer()
                    
                    responsePanel
                        .padding(.horizontal, 30)
                        .padding(.bottom, geometry.size.height * 0.08)
                        .opacity(responseOpacity)
                }
                
                processingOverlay
            }
        }
        .onAppear {
            setupInitialAnimations()
            prepareAudioSession()
        }
        .onDisappear {
            stopImageCapturing()
        }
    }
    
    // MARK: - View Components
    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 175/255, green: 196/255, blue: 214/255),
                    Color(red: 120/255, green: 150/255, blue: 190/255)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [Color.white.opacity(0.3), Color.clear]),
                        center: .center,
                        startRadius: 1,
                        endRadius: 200
                    )
                )
                .scaleEffect(1.5)
                .offset(x: -150, y: -300)
                .blur(radius: 15)
            
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [Color.purple.opacity(0.2), Color.clear]),
                        center: .center,
                        startRadius: 1,
                        endRadius: 250
                    )
                )
                .scaleEffect(2.0)
                .offset(x: 170, y: 300)
                .blur(radius: 20)
        }
    }
    
    private var titleView: some View {
        Text("Spectra")
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 3)
            .overlay(
                Text("Spectra")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.3))
                    .offset(x: 1, y: 1)
                    .blur(radius: 1)
            )
            .scaleEffect(titleScale)
            .animation(.spring(response: 1, dampingFraction: 0.7), value: appearingElements)
    }
    
    private var statusView: some View {
        Text(buttonStatusText)
            .font(.title3.weight(.medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.15))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 3)
            .transition(.scale.combined(with: .opacity))
            .id(buttonStatusText)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: buttonStatusText)
    }
    
    private var responsePanel: some View {
        VStack(spacing: 15) {
            VStack {
                if serverResponseText.isEmpty {
                    emptyResponseView
                } else {
                    filledResponseView
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 15)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.black.opacity(0.7),
                                Color(red: 30/255, green: 40/255, blue: 60/255).opacity(0.8)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.5),
                                        Color.purple.opacity(0.3)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
            )
            
            if let error = errorMessage {
                errorView(message: error)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    private var emptyResponseView: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 24))
                .foregroundColor(Color.blue.opacity(0.8))
            
            Text("Response will appear here")
                .font(.title3.weight(.medium))
                .foregroundColor(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
                .transition(.opacity)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 100)
    }
    
    private var filledResponseView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 20, weight: .semibold))
                
                Text("Response")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                Text(formattedTimestamp)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 5)
            
            Divider()
                .background(Color.white.opacity(0.3))
            
            ScrollView {
                Text(serverResponseText)
                    .font(.body.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(serverResponseText)
            }
            .frame(maxHeight: 200)
        }
        .padding(.horizontal, 10)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    private var processingOverlay: some View {
        Group {
            if isProcessingImage {
                ZStack {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("Processing...")
                            .font(.title3.weight(.medium))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 4) {
                            ForEach(0..<3) { index in
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 6, height: 6)
                                    .opacity(pulseAnimation && index % 3 == Int(Date().timeIntervalSince1970) % 3 ? 1 : 0.3)
                                    .animation(
                                        Animation.easeInOut(duration: 0.5)
                                            .repeatForever()
                                            .delay(Double(index) * 0.2),
                                        value: pulseAnimation
                                    )
                            }
                        }
                    }
                    .padding(30)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.5), radius: 15, x: 0, y: 10)
                    )
                    .transition(.scale.combined(with: .opacity))
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isProcessingImage)
    }
    
    private func errorView(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .font(.system(size: 16))
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Computed Properties for UI
    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
    
    // MARK: - Animation Setup
    private func setupInitialAnimations() {
        pulseAnimation = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                appearingElements = true
                titleScale = 1.0
            }
            
            withAnimation(.easeIn(duration: 0.8)) {
                responseOpacity = 1.0
            }
        }
        
        if isListening {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                gradientRotation = 360
            }
        }
    }
    
    // MARK: - Core Functionality
    private func prepareAudioSession() {
        AudioSessionManager.shared.activate()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                responseOpacity = 1.0
            }
        }
    }
    
    private func handleTapGesture() {
        generateHapticFeedback()
        
        isListening.toggle()
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            if isListening {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    gradientRotation = 360
                }
            } else {
                gradientRotation = 0
            }
        }
        
        if isListening {
            startListening()
        } else {
            stopListening()
        }
    }
    
    private func generateHapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
    
    private func startListening() {
        withAnimation(.easeInOut(duration: 0.3)) {
            buttonStatusText = "Listening..."
        }
        
        finalRecognizedText = ""
        serverResponseText = ""
        errorMessage = nil
        shouldCaptureImages = false
        
        speechRecognizers.startRecording { recognizedText in
            finalRecognizedText = recognizedText
            
            withAnimation(.easeInOut(duration: 0.3)) {
                isSpeaking = true
            }
            
            playFeedbackSound(for: .success)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isSpeaking = false
                }
            }
        }
        
        animateActiveState()
    }
    
    private func stopListening() {
        withAnimation(.easeInOut(duration: 0.3)) {
            buttonStatusText = "Processing request"
        }
        
        speechRecognizers.stopRecording()
        
        if !finalRecognizedText.isEmpty {
            sendRecognizedTextToServer(finalRecognizedText)
        } else {
            handleEmptyRecognition()
        }
        
        animateInactiveState()
    }
    
    private func animateActiveState() {
        withAnimation(
            .spring(response: 0.3, dampingFraction: 0.6)
            .repeatForever(autoreverses: true)
        ) {
            buttonScale = 1.05
        }
    }
    
    private func animateInactiveState() {
        withAnimation(.easeInOut(duration: 0.3)) {
            buttonScale = 1.0
        }
    }
    
    private func handleEmptyRecognition() {
        withAnimation(.easeInOut(duration: 0.3)) {
            buttonStatusText = "No speech detected"
        }
        
        playFeedbackSound(for: .error)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                buttonStatusText = "Awaiting command"
            }
        }
    }
    
    private func playFeedbackSound(for type: FeedbackType) {
        switch type {
        case .success:
            AudioServicesPlaySystemSound(1519)
        case .error:
            AudioServicesPlaySystemSound(1521)
        }
    }
    
    private enum FeedbackType {
        case success, error
    }
    
    private func sendRecognizedTextToServer(_ recognizedText: String) {
        withAnimation {
            buttonStatusText = "Sending request..."
        }
        
        apiService.sendSpeechCommand(recognizedText) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    handleSuccessfulResponse(response)
                case .failure(let error):
                    handleResponseError(error)
                }
            }
        }
    }
    
    private func handleSuccessfulResponse(_ response: String) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            serverResponseText = response
            buttonStatusText = "Command received"
        }
        
        playFeedbackSound(for: .success)
        
        if response.contains("point your camera") ||
           response.contains("describe what is") ||
           response.contains("locating the object") {
            startImageCapturing()
        }
    }
    
    private func handleResponseError(_ error: Error) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            errorMessage = "Failed to send command: \(error.localizedDescription)"
            buttonStatusText = "Command failed"
        }
        
        playFeedbackSound(for: .error)
    }
    
    // MARK: - Image Capture & Processing
    private func startImageCapturing() {
        stopImageCapturing()
        
        shouldCaptureImages = true
        
        withAnimation(.easeInOut(duration: 0.4)) {
            isProcessingImage = true
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        withAnimation {
            buttonStatusText = "Camera active"
        }
        
        cameraManager.startCapturingFrames { capturedImage in
            guard shouldCaptureImages else { return }
            
            if isProcessingImage {
                processImage(capturedImage)
            }
        }
    }
    
    private func processImage(_ image: UIImage) {
        withAnimation(.easeInOut(duration: 0.3).repeatForever()) {
            pulseAnimation = true
        }
        
        withAnimation {
            buttonStatusText = "Analyzing image..."
        }
        
        apiService.sendImage(image) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    handleSuccessfulImageProcessing(response.text, audioData: response.audioData)
                case .failure(let error):
                    handleImageProcessingError(error)
                }
                
                withAnimation(.easeInOut(duration: 0.3)) {
                    isProcessingImage = false
                }
            }
        }
    }
    
    private func handleSuccessfulImageProcessing(_ text: String, audioData: Data?) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            serverResponseText = text
            buttonStatusText = "Analysis complete"
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        if let audioData = audioData {
            apiService.playAudioData(audioData)
            
            withAnimation {
                buttonStatusText = "Playing audio response"
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if shouldCaptureImages {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isProcessingImage = true
                    buttonStatusText = "Capturing new image"
                }
            }
        }
    }
    
    private func handleImageProcessingError(_ error: Error) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            errorMessage = "Image processing error: \(error.localizedDescription)"
            buttonStatusText = "Analysis failed"
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if shouldCaptureImages {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isProcessingImage = true
                    buttonStatusText = "Retrying analysis"
                }
            }
        }
    }
    
    private func stopImageCapturing() {
        shouldCaptureImages = false
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isProcessingImage = false
        }
        
        cameraManager.stop()
        
        withAnimation {
            buttonStatusText = "Awaiting command"
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            pulseAnimation = false
        }
    }
}
