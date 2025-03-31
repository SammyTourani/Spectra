import SwiftUI
import AVFoundation
import Speech

// MARK: - OnBoardingView
struct OnBoardingView: View {
    // MARK: - Properties
    let onComplete: () -> Void
    
    // MARK: - View Model
    @StateObject private var viewModel = OnboardingViewModel()
    private let ttsManager = AzureTTSManager.shared
    
    // MARK: - Animation States
    @State private var appearAnimation = false
    @State private var titleOffset: CGFloat = -50
    @State private var headingOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var contentScale: CGFloat = 0.9
    
    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // MARK: - Background
                DynamicWaveBackground()
                    .ignoresSafeArea()
                
                // MARK: - Content
                VStack(spacing: 40) {
                    // MARK: - Title
                    Text("Let's Get Started")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .padding(.top, 40)
                        .offset(y: titleOffset)
                        .opacity(headingOpacity)
                    
                    // MARK: - Main Content
                    ZStack {
                        if viewModel.currentStep == .initial || viewModel.currentStep == .playing || viewModel.currentStep == .listening {
                            mainContentView(geometry: geometry)
                                .transition(
                                    .asymmetric(
                                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                                        removal: .scale(scale: 1.1).combined(with: .opacity)
                                    )
                                )
                        }
                        
                        if viewModel.currentStep == .success {
                            successView(geometry: geometry)
                                .transition(
                                    .asymmetric(
                                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                                        removal: .scale(scale: 1.2).combined(with: .opacity)
                                    )
                                )
                        }
                    }
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: viewModel.currentStep)
                    .frame(height: geometry.size.height * 0.5)
                    .opacity(contentOpacity)
                    .scaleEffect(contentScale)
                    
                    // MARK: - Progress Indicator
                    ProgressDotsView(currentStep: viewModel.getStepIndex())
                        .padding(.bottom, 20)
                        .opacity(contentOpacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                headingOpacity = 1
                titleOffset = 0
            }
            
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                contentOpacity = 1
                contentScale = 1
            }
            
            viewModel.startOnboarding { [weak viewModel] in
                guard let viewModel = viewModel else { return }
                
                viewModel.setupSpeechRecognition {
                    ttsManager.speak("Awesome, I can hear you loud and clear! Let's keep going.", voice: "en-US-JennyNeural") {
                        viewModel.cleanupResources()
                        onComplete()
                    }
                }
            }
        }
        .onDisappear {
            viewModel.cleanupResources()
        }
    }
    
    // MARK: - Main Content View
    private func mainContentView(geometry: GeometryProxy) -> some View {
        VStack(spacing: 20) {
            if viewModel.currentStep != .listening {
                // MARK: - Speaking Animation
                SpeakingAnimationView(playing: viewModel.currentStep == .playing)
                    .frame(width: geometry.size.width * 0.5, height: geometry.size.width * 0.5)
            } else {
                // MARK: - Listening Animation
                ListeningAnimationView(active: viewModel.currentStep == .listening)
                    .frame(width: geometry.size.width * 0.5, height: geometry.size.width * 0.5)
            }
            
            // MARK: - Instruction Text
            InstructionTextView(text: viewModel.instructionText, isListening: viewModel.currentStep == .listening)
                .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Success View
    private func successView(geometry: GeometryProxy) -> some View {
        VStack(spacing: 20) {
            SuccessAnimationView(showAnimation: viewModel.showSuccessAnimation)
                .frame(width: geometry.size.width * 0.5, height: geometry.size.width * 0.5)
            
            Text("Great! Mic test successful.")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .opacity(viewModel.showSuccessAnimation ? 1 : 0)
                .offset(y: viewModel.showSuccessAnimation ? 0 : 20)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.3), value: viewModel.showSuccessAnimation)
        }
    }
}

// MARK: - OnboardingViewModel
final class OnboardingViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var currentStep: OnboardingStep = .initial
    @Published var instructionText: String = "Spectra is explaining how to use the app"
    @Published var showSuccessAnimation = false
    
    // MARK: - Private Properties
    private var audioManager = AudioManager()
    private var speechRecognizers = SpeechRecognizers()
    private var retryCount = 0
    private var isTransitioning = false
    
    // MARK: - Onboarding Steps
    enum OnboardingStep {
        case initial
        case playing
        case listening
        case success
    }
    
    // MARK: - Public Methods
    func startOnboarding(completion: @escaping () -> Void) {
        print("Starting onboarding")
        currentStep = .playing
        
        AudioSessionManager.shared.deactivate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            AudioSessionManager.shared.activate()
            
            let audioStartTime = Date()
            
            self.audioManager.playAudio(named: "onboarding_audio") {
                print("Onboarding audio finished naturally")
                let playbackDuration = Date().timeIntervalSince(audioStartTime)
                if playbackDuration >= 5.0 && self.currentStep == .playing {
                    DispatchQueue.main.async {
                        print("Audio played for sufficient duration, proceeding")
                        completion()
                    }
                }
            }
        }
    }
    
    func setupSpeechRecognition(successCompletion: @escaping () -> Void) {
        guard currentStep == .playing else {
            print("Speech recognition setup skipped - wrong state: \(currentStep)")
            return
        }
        
        print("Setting up speech recognition")
        withAnimation(.easeInOut(duration: 0.4)) {
            currentStep = .listening
            instructionText = retryCount > 0 ? "Say 'Begin' again (\(retryCount + 1)/3)" : "Say 'Begin' to continue..."
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
                    self.handleSuccess(completion: successCompletion)
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) {
                if self.currentStep == .listening && self.retryCount < 2 {
                    print("Speech timeout, prompting retry")
                    self.speechRecognizers.stopRecording()
                    self.retryCount += 1
                    withAnimation(.easeInOut(duration: 0.4)) {
                        self.instructionText = "I didn't hear 'Begin'. Try again (\(self.retryCount + 1)/3)."
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.setupSpeechRecognition(successCompletion: successCompletion)
                    }
                } else if self.currentStep == .listening {
                    print("Max retries reached, moving forward")
                    self.handleSuccess(completion: successCompletion)
                }
            }
        }
    }
    
    func cleanupResources() {
        speechRecognizers.stopRecording()
        audioManager.stopAudio()
        AzureTTSManager.shared.cancelAllSpeech()
        AudioSessionManager.shared.deactivate()
    }
    
    func getStepIndex() -> Int {
        switch currentStep {
        case .initial, .playing: return 1
        case .listening: return 2
        case .success: return 3
        }
    }
    
    // MARK: - Private Methods
    private func handleSuccess(completion: @escaping () -> Void) {
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
                    completion()
                }
            }
        }
    }
}

// MARK: - Dynamic Wave Background
struct DynamicWaveBackground: View {
    @State private var phase: Double = 0.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base gradient - using your original colors
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 46/255, green: 49/255, blue: 146/255),
                        Color(red: 27/255, green: 255/255, blue: 255/255)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Moving waves
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        // Slow down the animation by dividing the time interval
                        let now = timeline.date.timeIntervalSinceReferenceDate
                        // Use a much slower speed factor (0.05 instead of 1.0)
                        let speed = 0.3
                        // Remove truncatingRemainder to prevent the jerky reset
                        let adjustedPhase = now * speed
                        
                        for wave in 0..<3 {
                            let waveOffset = Double(wave) * 1.7
                            let path = Path { path in
                                path.move(to: CGPoint(x: 0, y: size.height * 0.5))
                                for x in stride(from: 0, through: size.width, by: 1) {
                                    // Reduce the frequency to slow down wave movement
                                    let y = size.height * 0.5 +
                                            sin(adjustedPhase + Double(x) / 200 + waveOffset) * 60 +
                                            cos(adjustedPhase * 0.7 + Double(x) / 300 + waveOffset) * 30
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                                
                                // Complete the path for filling
                                path.addLine(to: CGPoint(x: size.width, y: size.height))
                                path.addLine(to: CGPoint(x: 0, y: size.height))
                                path.closeSubpath()
                            }
                            context.fill(
                                path,
                                with: .color(Color.white.opacity(0.2 - Double(wave) * 0.05))
                            )
                        }
                    }
                }
                
                // Subtle floating particles for added depth
                FloatingParticlesView()
                    .opacity(0.3)
            }
        }
    }
}
// MARK: - Floating Particles View
struct FloatingParticlesView: View {
    let particleCount = 20
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<particleCount, id: \.self) { index in
                    ParticleView(
                        size: CGFloat.random(in: 2...4),
                        position: randomPosition(in: geometry.size),
                        duration: Double.random(in: 20...40),
                        delay: Double.random(in: 0...10)
                    )
                }
            }
        }
    }
    
    private func randomPosition(in size: CGSize) -> CGPoint {
        return CGPoint(
            x: CGFloat.random(in: 0...size.width),
            y: CGFloat.random(in: 0...size.height)
        )
    }
}

// MARK: - Particle View
struct ParticleView: View {
    let size: CGFloat
    let position: CGPoint
    let duration: Double
    let delay: Double
    
    @State private var opacity: Double = 0
    @State private var yOffset: CGFloat = 0
    
    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: size, height: size)
            .position(position)
            .offset(y: yOffset)
            .opacity(opacity)
            .blur(radius: 0.5)
            .onAppear {
                let baseDelay = delay
                
                withAnimation(
                    Animation
                        .easeInOut(duration: duration)
                        .repeatForever(autoreverses: false)
                        .delay(baseDelay)
                ) {
                    yOffset = -100 - CGFloat.random(in: 0...100)
                }
                
                withAnimation(
                    Animation
                        .easeInOut(duration: duration * 0.2)
                        .delay(baseDelay)
                ) {
                    opacity = Double.random(in: 0.2...0.5)
                }
                
                withAnimation(
                    Animation
                        .easeInOut(duration: duration * 0.2)
                        .delay(baseDelay + duration * 0.8)
                ) {
                    opacity = 0
                }
            }
    }
}

// MARK: - Speaking Animation View
struct SpeakingAnimationView: View {
    let playing: Bool
    
    @State private var waveScale: CGFloat = 1.0
    @State private var waveOpacity: Double = 0.5
    @State private var circleScale: [CGFloat] = [1.0, 1.0, 1.0]
    
    var body: some View {
        ZStack {
            // Outer circles
            ForEach(0..<3) { i in
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.8), .blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 120 + CGFloat(i * 30), height: 120 + CGFloat(i * 30))
                    .scaleEffect(playing ? circleScale[i] : 1.0)
                    .opacity(waveOpacity / Double(i + 1))
                    .blur(radius: CGFloat(i))
            }
            
            // Inner animated circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue.opacity(0.7), .cyan.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 100, height: 100)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.4), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.2), radius: 10)
            
            // Icon
            Image(systemName: "waveform.circle.fill")
                .resizable()
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .cyan.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 60, height: 60)
                .shadow(color: .black.opacity(0.3), radius: 5)
        }
        .onAppear {
            if playing {
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    waveOpacity = 0.8
                    circleScale = [1.1, 1.15, 1.2]
                }
            }
        }
        .onChange(of: playing) { _, newValue in
            if newValue {
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    waveOpacity = 0.8
                    circleScale = [1.1, 1.15, 1.2]
                }
            } else {
                withAnimation(.easeOut(duration: 0.5)) {
                    waveOpacity = 0.5
                    circleScale = [1.0, 1.0, 1.0]
                }
            }
        }
    }
}

// MARK: - Listening Animation View
struct ListeningAnimationView: View {
    let active: Bool
    
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // Pulse circles
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.blue.opacity(0.5), .blue.opacity(0.01)],
                        center: .center,
                        startRadius: 50,
                        endRadius: 120
                    )
                )
                .frame(width: 160, height: 160)
                .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                .opacity(pulseAnimation ? 0.8 : 0.4)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.blue.opacity(0.7), .blue.opacity(0.3)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 80
                    )
                )
                .frame(width: 120, height: 120)
                .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                .blur(radius: 1)
            
            // Main circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue.opacity(0.9), .purple.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 100, height: 100)
                .shadow(color: .black.opacity(0.3), radius: 5)
            
            // Microphone icon
            Image(systemName: "mic.fill")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.4), radius: 2)
        }
        .onAppear {
            if active {
                withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            }
        }
        .onChange(of: active) { _, newValue in
            if newValue {
                withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.5)) {
                    pulseAnimation = false
                }
            }
        }
    }
}

// MARK: - Success Animation View
struct SuccessAnimationView: View {
    let showAnimation: Bool
    
    @State private var outerRingScale: CGFloat = 0.8
    @State private var innerRingScale: CGFloat = 0.8
    @State private var checkmarkScale: CGFloat = 0.01
    @State private var checkmarkOpacity: Double = 0
    @State private var particlesOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.green.opacity(0.7), .green.opacity(0.1)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 100
                    )
                )
                .frame(width: 160, height: 160)
                .scaleEffect(outerRingScale)
                .opacity(showAnimation ? 1 : 0)
            
            // Inner ring
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.green.opacity(0.9), .green.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .scaleEffect(innerRingScale)
                .shadow(color: .black.opacity(0.3), radius: 10)
            
            // Success particles
            ForEach(0..<12) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white)
                    .frame(width: 4, height: 15)
                    .offset(y: -70)
                    .rotationEffect(.degrees(Double(i) * 30))
                    .opacity(particlesOpacity * (i % 2 == 0 ? 1 : 0.7))
                    .animation(
                        .easeOut(duration: 0.5).delay(Double(i) * 0.05),
                        value: particlesOpacity
                    )
            }
            
            // Checkmark
            Image(systemName: "checkmark")
                .font(.system(size: 60, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .scaleEffect(checkmarkScale)
                .opacity(checkmarkOpacity)
                .shadow(color: .black.opacity(0.2), radius: 1)
        }
        .onAppear {
            if showAnimation {
                animateSuccess()
            }
        }
        .onChange(of: showAnimation) { _, newValue in
            if newValue {
                animateSuccess()
            } else {
                resetAnimation()
            }
        }
    }
    
    private func animateSuccess() {
        // Animate outer ring
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            outerRingScale = 1.2
        }
        
        // Animate inner ring with a slight delay
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
            innerRingScale = 1.0
        }
        
        // Animate checkmark
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.2)) {
            checkmarkScale = 1.0
            checkmarkOpacity = 1.0
        }
        
        // Animate particles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.5)) {
                particlesOpacity = 1.0
            }
            
            // Fade out particles
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 0.7)) {
                    particlesOpacity = 0.0
                }
            }
        }
    }
    
    private func resetAnimation() {
        withAnimation(.easeOut(duration: 0.3)) {
            outerRingScale = 0.8
            innerRingScale = 0.8
            checkmarkScale = 0.01
            checkmarkOpacity = 0
            particlesOpacity = 0
        }
    }
}

// MARK: - Instruction Text View
struct InstructionTextView: View {
    let text: String
    let isListening: Bool
    
    @State private var textScale: CGFloat = 1.0
    
    var body: some View {
        Text(text)
            .font(.system(size: isListening ? 22 : 18, weight: isListening ? .semibold : .regular, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [.white, .white.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .multilineTextAlignment(.center)
            .padding(.horizontal, 25)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(.ultraThinMaterial.opacity(0.3))
                    .blur(radius: 0.5)
                    .opacity(isListening ? 0.7 : 0)
            )
            .scaleEffect(textScale)
            .shadow(color: .black.opacity(0.15), radius: 1)
            .onChange(of: text) { _, _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    textScale = 1.05
                }
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1)) {
                    textScale = 1.0
                }
            }
    }
}

// MARK: - Progress Dots View
struct ProgressDotsView: View {
    let currentStep: Int
    
    @State private var bounceAnimation = false
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(1...3, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? Color.white : Color.white.opacity(0.4))
                    .frame(width: step == currentStep ? 12 : 10, height: step == currentStep ? 12 : 10)
                    .scaleEffect(step == currentStep && bounceAnimation ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: currentStep)
                    .shadow(color: step <= currentStep ? .white.opacity(0.5) : .clear, radius: 2)
            }
        }
        .onChange(of: currentStep) { _, _ in
            bounceAnimation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                bounceAnimation = false
            }
        }
    }
}
