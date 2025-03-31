import SwiftUI
import AVFoundation
import Speech

struct OnBoardingView: View {
    let onComplete: () -> Void
    
    @StateObject private var audioManager = AudioManager()
    @StateObject private var speechRecognizers = SpeechRecognizers()
    private let ttsManager = AzureTTSManager.shared
    @State private var currentStep: OnboardingStep = .initial
    @State private var pulseAnimation = false
    @State private var waveScale: CGFloat = 1.0
    @State private var waveOpacity: Double = 0.5
    @State private var showSuccessAnimation = false
    @State private var instructionText: String = "Spectra is explaining how to use the app"
    @State private var isTransitioning = false
    @State private var retryCount = 0 // Added for retry feedback
    
    enum OnboardingStep {
        case initial
        case playing
        case listening
        case success
    }
    
    var body: some View {
        ZStack {
            DynamicWaveBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Text("Let's Get Started")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
                
                ZStack {
                    if currentStep == .initial || currentStep == .playing || currentStep == .listening {
                        VStack(spacing: 20) {
                            if currentStep != .listening {
                                ZStack {
                                    ForEach(0..<3) { i in
                                        Circle()
                                            .stroke(Color.white.opacity(waveOpacity / Double(i + 1)), lineWidth: 3)
                                            .frame(width: 120 + CGFloat(i * 30), height: 120 + CGFloat(i * 30))
                                            .scaleEffect(currentStep == .playing ? waveScale : 1.0)
                                    }
                                    Image(systemName: "waveform.circle.fill")
                                        .resizable()
                                        .foregroundColor(.white)
                                        .frame(width: 80, height: 80)
                                        .shadow(color: .black.opacity(0.2), radius: 5)
                                }
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 160, height: 160)
                                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                                    Circle()
                                        .fill(Color.white.opacity(0.4))
                                        .frame(width: 120, height: 120)
                                        .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                                    Circle()
                                        .fill(Color.blue.opacity(0.7))
                                        .frame(width: 100, height: 100)
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.white)
                                }
                            }
                            
                            Text(instructionText)
                                .font(.system(size: currentStep == .listening ? 22 : 18, weight: currentStep == .listening ? .semibold : .regular))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                                    removal: .scale(scale: 1.1).combined(with: .opacity)
                                ))
                        }
                    }
                    
                    if currentStep == .success {
                        VStack(spacing: 20) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.3))
                                    .frame(width: 160, height: 160)
                                    .scaleEffect(showSuccessAnimation ? 1.2 : 0.8)
                                Circle()
                                    .fill(Color.green.opacity(0.7))
                                    .frame(width: 120, height: 120)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.white)
                                    .offset(y: showSuccessAnimation ? 0 : 50)
                                    .opacity(showSuccessAnimation ? 1 : 0)
                            }
                            Text("Great! Mic test successful.")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                                .opacity(showSuccessAnimation ? 1 : 0)
                                .offset(y: showSuccessAnimation ? 0 : 20)
                        }
                    }
                }
                
                HStack(spacing: 12) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(i < getStepIndex() ? Color.white : Color.white.opacity(0.4))
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            startOnboarding()
        }
        .onDisappear {
            cleanupResources()
        }
    }
    
    private func startOnboarding() {
        print("Starting onboarding")
        currentStep = .playing
        
        withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            waveScale = 1.2
            waveOpacity = 0.8
        }
        
        AudioSessionManager.shared.deactivate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            AudioSessionManager.shared.activate()
            
            let audioStartTime = Date()
            
            audioManager.playAudio(named: "onboarding_audio") {
                print("Onboarding audio finished naturally")
                let playbackDuration = Date().timeIntervalSince(audioStartTime)
                if playbackDuration >= 5.0 && self.currentStep == .playing {
                    DispatchQueue.main.async {
                        print("Audio played for sufficient duration, proceeding to speech recognition")
                        self.setupSpeechRecognition()
                    }
                }
            }
        }
    }
    
    private func setupSpeechRecognition() {
        guard currentStep == .playing else {
            print("Speech recognition setup skipped - wrong state: \(currentStep)")
            return
        }
        
        print("Setting up speech recognition")
        withAnimation(.easeInOut(duration: 0.4)) {
            currentStep = .listening
            instructionText = retryCount > 0 ? "Say 'Begin' again (\(retryCount + 1)/3)" : "Say 'Begin' to continue..."
        }
        
        withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseAnimation = true
        }
        
        let micPermission = AVAudioSession.sharedInstance().recordPermission
        guard micPermission == .granted else {
            print("Microphone permission denied: \(micPermission.rawValue)")
            currentStep = .initial
            instructionText = "Please enable microphone access in Settings."
            return
        }
        
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            print("Speech recognition not authorized")
            currentStep = .initial
            instructionText = "Please enable speech recognition in Settings."
            return
        }
        
        AudioSessionManager.shared.deactivate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            AudioSessionManager.shared.activate()
            self.speechRecognizers.startRecording { recognizedText in
                print("Recognized text: \(recognizedText)")
                if recognizedText.lowercased().contains("begin") {
                    self.handleSuccess()
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) { // Extended timeout to 20 seconds
                if self.currentStep == .listening && self.retryCount < 2 {
                    print("Speech timeout, prompting retry")
                    self.speechRecognizers.stopRecording()
                    self.retryCount += 1
                    withAnimation(.easeInOut(duration: 0.4)) {
                        self.instructionText = "I didn't hear 'Begin'. Try again (\(self.retryCount + 1)/3)."
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.setupSpeechRecognition()
                    }
                } else if self.currentStep == .listening {
                    print("Max retries reached, moving forward")
                    self.handleSuccess() // Proceed anyway after 3 tries
                }
            }
        }
    }
    
    private func handleSuccess() {
        guard !isTransitioning, currentStep != .success else {
            print("Success already handled, ignoring duplicate")
            return
        }
        
        print("Handling success after 'Begin' detected")
        isTransitioning = true
        speechRecognizers.stopRecording()
        
        withAnimation {
            currentStep = .success
            print("UI updated to success state")
        }
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            showSuccessAnimation = true
            print("Success animation triggered")
        }
        
        AudioSessionManager.shared.deactivate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            AudioSessionManager.shared.activate()
            self.audioManager.playAudio(named: "success_chime") {
                print("Success chime finished")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("Preparing to play TTS")
                    self.ttsManager.speak("Awesome, I can hear you loud and clear! Let's keep going.", voice: "en-US-JennyNeural") {
                        print("TTS finished - preparing for navigation")
                        self.speechRecognizers.stopRecording()
                        self.audioManager.stopAudio()
                        AudioSessionManager.shared.deactivate()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            print("All resources cleaned up, proceeding with navigation")
                            self.onComplete()
                        }
                    }
                }
            }
        }
    }
    
    private func cleanupResources() {
        speechRecognizers.stopRecording()
        audioManager.stopAudio()
        ttsManager.cancelAllSpeech()
        AudioSessionManager.shared.deactivate()
    }
    
    private func getStepIndex() -> Int {
        switch currentStep {
        case .initial, .playing: return 1
        case .listening: return 2
        case .success: return 3
        }
    }
}

struct DynamicWaveBackground: View {
    @State private var phase: Double = 0.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 46/255, green: 49/255, blue: 146/255),
                        Color(red: 27/255, green: 255/255, blue: 255/255)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                Canvas { context, size in
                    for wave in 0..<3 {
                        let waveOffset = Double(wave) * 0.5
                        let path = Path { path in
                            path.move(to: CGPoint(x: 0, y: size.height * 0.5))
                            for x in stride(from: 0, through: size.width, by: 1) {
                                let y = size.height * 0.5 +
                                        sin(phase + Double(x) / 100 + waveOffset) * 60 +
                                        cos(phase * 0.7 + Double(x) / 150 + waveOffset) * 30
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        context.stroke(
                            path,
                            with: .color(Color.white.opacity(0.2 - Double(wave) * 0.05)),
                            lineWidth: 2
                        )
                    }
                }
            }
            .onAppear {
                withAnimation(Animation.linear(duration: 4).repeatForever(autoreverses: false)) {
                    phase = 2 * .pi
                }
            }
        }
    }
}
