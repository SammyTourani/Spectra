import SwiftUI
import AVFoundation
import Speech

struct NameInputView: View {
    let selectedVoice: String
    let onComplete: (String) -> Void
    
    @StateObject private var speechRecognizers = SpeechRecognizers()
    @StateObject private var ttsManager = AzureTTSManager(
        apiKey: "BcZtnvJFdIxg9rexNdQUwOQYFay9YaGZMPUkBKPfgtE8VBEbQIgJJQQJ99BCACBsN54XJ3w3AAAYACOGpSuV",
        region: "canadacentral"
    )
    @StateObject private var audioManager = AudioManager()
    
    // State variables
    @State private var userName: String = ""
    @State private var isListening: Bool = false
    @State private var listeningText: String = "Say your name..."
    @State private var typingIndex: Int = 0
    @State private var typingInProgress: Bool = false
    @State private var showConfirmation: Bool = false
    @State private var greetingPlayed: Bool = false
    @State private var pulseAnimation: Bool = false
    @State private var particles: [BackgroundParticle] = []
    @State private var titleOpacity: Double = 0
    @State private var containerOpacity: Double = 0
    @State private var borderRotation: Double = 0
    @State private var introductionStarted = false
    @State private var nameRevealCompleted = false
    
    // Flag to prevent multiple navigation attempts
    @State private var hasTriggeredTransition = false
    
    // For audio playback optimization
    @State private var audioPlayer: AVAudioPlayer? = nil
    
    // For animation performance
    @Environment(\.scenePhase) private var scenePhase
    
    // Timer reference for proper cleanup
    @State private var typingTimer: Timer? = nil
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Elegant gradient background - using .drawingGroup() for metal acceleration
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 46/255, green: 49/255, blue: 146/255),
                        Color(red: 27/255, green: 205/255, blue: 255/255)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                // Animated particles - reduced count and using drawingGroup
                ForEach(particles) { particle in
                    Circle()
                        .fill(Color.white)
                        .opacity(particle.opacity)
                        .frame(width: particle.size, height: particle.size)
                        .position(particle.position)
                        .blur(radius: particle.size * 0.2)
                }
                .drawingGroup() // Use Metal acceleration
                
                // Subtle wave overlay - using drawingGroup for better performance
                WaveOverlay()
                    .ignoresSafeArea()
                    .opacity(0.2)
                    .drawingGroup() // Use Metal acceleration
                
                VStack(spacing: 40) {
                    Text("What's Your Name?")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.2), radius: 2)
                        .padding(.top, 60)
                        .opacity(titleOpacity)
                    
                    Spacer()
                    
                    // Main container
                    ZStack {
                        // Container with fade-in animation
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 280, height: 280)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.3), radius: 20)
                            .opacity(containerOpacity)
                        
                        if isListening {
                            // Listening animation - reduced layers and using drawingGroup
                            ForEach(0..<2) { i in
                                Circle()
                                    .stroke(Color.white.opacity(0.2 - Double(i) * 0.05), lineWidth: 2)
                                    .frame(width: 300 + CGFloat(i * 30), height: 300 + CGFloat(i * 30))
                                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                            }
                            .drawingGroup() // Use Metal acceleration
                            
                            // Animated listening icon with text
                            VStack(spacing: 20) {
                                Image(systemName: "waveform.circle.fill")
                                    .font(.system(size: 70))
                                    .foregroundColor(.white)
                                    .shadow(color: Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.5), radius: 10)
                                
                                Text(listeningText)
                                    .font(.system(size: 22, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .transition(.opacity)
                        } else if typingInProgress {
                            // Typing animation
                            Text(String(userName.prefix(typingIndex)) + (typingIndex < userName.count ? "|" : ""))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.5), radius: 5)
                        } else if showConfirmation {
                            // Cool border around the name - using drawingGroup for better performance
                            ZStack {
                                // Outer rotating border - reduced to one layer
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 27/255, green: 205/255, blue: 255/255),
                                                Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.5),
                                                Color(red: 46/255, green: 49/255, blue: 146/255).opacity(0.8),
                                                Color(red: 27/255, green: 205/255, blue: 255/255)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 3
                                    )
                                    .frame(width: 235, height: 135)
                                    .rotationEffect(Angle(degrees: borderRotation))
                                    .opacity(0.7)
                                    .drawingGroup() // Use Metal acceleration
                                
                                // Inner container for name
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 220, height: 120)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                                
                                // Name display
                                VStack(spacing: greetingPlayed ? 12 : 0) {
                                    Text(userName)
                                        .font(.system(size: 38, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .shadow(color: Color(red: 27/255, green: 205/255, blue: 255/255), radius: 10)
                                        .padding(.horizontal, 20)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    
                                    if greetingPlayed {
                                        Text("Nice to meet you!")
                                            .font(.system(size: 18, weight: .medium, design: .rounded))
                                            .foregroundColor(.white.opacity(0.8))
                                            .opacity(greetingPlayed ? 1 : 0)
                                    }
                                }
                            }
                            .opacity(nameRevealCompleted ? 1 : 0)
                            .animation(.easeIn(duration: 0.8), value: nameRevealCompleted)
                        } else {
                            // Initial state
                            VStack(spacing: 20) {
                                Image(systemName: "mic.circle.fill")
                                    .font(.system(size: 70))
                                    .foregroundColor(.white)
                                    .shadow(color: Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.5), radius: 10)
                                
                                Text(listeningText)
                                    .font(.system(size: 22, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .transition(.opacity)
                            .opacity(introductionStarted ? 1 : 0)
                        }
                    }
                    
                    Spacer()
                }
            }
            // Handle scenePhase changes - fixed for compatibility
            .onChange(of: scenePhase) { newPhase in
                // Pause heavy animations when app goes to background
                if newPhase != .active {
                    pauseHeavyAnimations()
                } else if newPhase == .active {
                    resumeAnimations()
                }
            }
            .onAppear {
                print("NameInputView: appeared")
                
                // Initialize audio player on appear to avoid the nil unwrapping crash
                initializeAudioPlayer()
                
                // Generate fewer particles for better performance
                generateParticles(in: geometry.size, count: 15)
                
                // Reset the transition flag on appear
                hasTriggeredTransition = false
                
                // Animate title and container
                withAnimation(.easeIn(duration: 1.0)) {
                    titleOpacity = 1
                    containerOpacity = 1
                }
                
                // Start introduction with a slight delay to allow the view transition to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    startIntroduction()
                    introductionStarted = true
                    
                    // Start pulse animation
                    withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        pulseAnimation = true
                    }
                }
                
                // Start rotating border - reduced animation calculation frequency
                withAnimation(Animation.linear(duration: 20).repeatForever(autoreverses: false).speed(0.5)) {
                    borderRotation = 360
                }
            }
            .onDisappear {
                print("NameInputView: disappeared")
                cleanupResources()
            }
        }
    }
    
    // MARK: - Initialization
    
    // Initialize audio player separately to avoid the nil unwrapping crash
    private func initializeAudioPlayer() {
        do {
            if let keyPressURL = Bundle.main.url(forResource: "key_press", withExtension: "mp3") {
                self.audioPlayer = try AVAudioPlayer(contentsOf: keyPressURL)
                self.audioPlayer?.prepareToPlay()
                self.audioPlayer?.volume = 0.2
                print("Audio player initialized successfully")
            } else {
                print("Warning: Could not find key_press.mp3 in bundle")
            }
        } catch {
            print("Error initializing audio player: \(error)")
        }
    }
    
    // MARK: - Interaction Methods
    
    private func startIntroduction() {
        AudioSessionManager.shared.activate()
        
        print("Starting introduction with voice: \(selectedVoice)")
        
        // First try with Azure TTS
        ttsManager.speak("Please say your name so I can greet you properly.", voice: selectedVoice) {
            // Add a fallback audio file in case TTS fails
            if !self.isListening {
                self.audioManager.playAudio(named: "name_prompt") {
                    self.startListening()
                }
            }
            
            AudioSessionManager.shared.deactivate()
            self.startListening()
        }
        
        // Safety timeout in case TTS callback fails
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if !self.isListening {
                print("NameInputView: TTS intro timeout, starting listening")
                self.startListening()
            }
        }
    }
    
    private func startListening() {
        isListening = true
        AudioSessionManager.shared.activate()
        listeningText = "I'm listening..."
        
        speechRecognizers.startRecording { recognizedText in
            if !recognizedText.isEmpty && recognizedText.count > 2 {
                // Stop recording after we detect something that might be a name
                self.speechRecognizers.stopRecording()
                self.isListening = false
                
                // Format the name (capitalize first letter of each word)
                let formattedName = recognizedText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: " ")
                    .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                    .joined(separator: " ")
                
                self.processCapturedName(formattedName)
            }
        }
    }
    
    private func processCapturedName(_ name: String) {
        print("NameInputView: Processing captured name: \(name)")
        
        userName = name
        listeningText = ""
        
        // Start typing animation
        typingInProgress = true
        typingIndex = 0
        
        // Clean up any existing timer
        typingTimer?.invalidate()
        
        // Animate typing one character at a time - more efficient timer handling
        typingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if self.typingIndex < self.userName.count {
                self.typingIndex += 1
                
                // Play sound only if player exists
                if let player = self.audioPlayer, player.isReady {
                    AudioSessionManager.shared.activate()
                    player.play()
                    player.currentTime = 0
                    AudioSessionManager.shared.deactivate()
                }
            } else {
                timer.invalidate()
                self.typingTimer = nil
                
                // Short pause after typing completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.typingInProgress = false
                    self.showConfirmation = true
                    
                    // Reveal the name with animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.nameRevealCompleted = true
                        
                        // Play greeting with the name after border animation appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            self.playGreetingAndTransition()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - New method for greeting and transition
    private func playGreetingAndTransition() {
        // Prevent multiple calls
        guard !greetingPlayed && !hasTriggeredTransition else {
            print("NameInputView: Already played greeting or triggered transition")
            return
        }
        
        print("NameInputView: Playing greeting for name: \(self.userName)")
        
        // Activate audio session for TTS
        AudioSessionManager.shared.activate()
        
        // Play the greeting with TTS
        ttsManager.speak("Hi \(self.userName)! It's nice to meet you, let's take you to the home menu.", voice: selectedVoice) { [self] in
            print("NameInputView: TTS greeting finished, preparing for transition")
            
            // Mark greeting as played immediately
            self.greetingPlayed = true
            
            // Use a reliable delay before transition
            self.triggerScreenTransition()
        }
        
        // Failsafe in case TTS completion doesn't fire
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            if !self.hasTriggeredTransition {
                print("NameInputView: TTS completion failsafe triggered")
                self.greetingPlayed = true
                self.triggerScreenTransition()
            }
        }
    }
    
    // MARK: - Separate method for screen transition with guard
    private func triggerScreenTransition() {
        // Prevent multiple transitions
        if hasTriggeredTransition {
            print("NameInputView: Transition already triggered, ignoring duplicate")
            return
        }
        
        print("NameInputView: Triggering transition to HomeView")
        
        // Set flag to prevent duplicate transitions
        hasTriggeredTransition = true
        
        // Cancel any TTS that might still be playing
        ttsManager.cancelAllSpeech()
        
        // Deactivate audio session
        AudioSessionManager.shared.deactivate()
        
        // Wait briefly then call the completion handler
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("NameInputView: Executing onComplete(\(self.userName))")
            
            // Call the completion handler provided by parent
            self.onComplete(self.userName)
        }
    }
    
    // MARK: - Helper Functions
    
    private func generateParticles(in size: CGSize, count: Int) {
        // Use fewer particles for better performance
        particles = (0..<count).map { _ in
            let position = CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height)
            )
            return BackgroundParticle(
                position: position,
                targetPosition: CGPoint(
                    x: position.x + CGFloat.random(in: -80...80),
                    y: position.y + CGFloat.random(in: -80...80)
                ),
                size: CGFloat.random(in: 2...6),
                opacity: Double.random(in: 0.1...0.3),
                animationDuration: Double.random(in: 20...35) // Slower animation for better performance
            )
        }
        
        // Animate particles
        for i in particles.indices {
            withAnimation(.linear(duration: particles[i].animationDuration).repeatForever(autoreverses: true)) {
                particles[i].position = particles[i].targetPosition
            }
        }
    }
    
    private func pauseHeavyAnimations() {
        // Stop any unnecessary animations or processing when app is in background
        typingTimer?.invalidate()
        typingTimer = nil
    }
    
    private func resumeAnimations() {
        // Could resume animations if needed
    }
    
    private func cleanupResources() {
        print("NameInputView: Cleaning up resources")
        
        // Ensure timers are invalidated
        typingTimer?.invalidate()
        typingTimer = nil
        
        // Stop audio playback
        audioPlayer?.stop()
        
        // Ensure speech recognition is stopped
        speechRecognizers.stopRecording()
        
        // Cancel any TTS
        ttsManager.cancelAllSpeech()
        
        // Deactivate audio session
        AudioSessionManager.shared.deactivate()
    }
}

// MARK: - Supporting Types and Views

// Background particle model
struct BackgroundParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    let targetPosition: CGPoint
    let size: CGFloat
    let opacity: Double
    let animationDuration: Double
}

// Optimized wave overlay - cached paths for better performance
struct WaveOverlay: View {
    @State private var phase1: Double = 0
    @State private var phase2: Double = 0
    @State private var phase3: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Reduced number of waves and using drawingGroup()
                SinWave(phase: phase1, strength: 20, frequency: 0.1)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                    .frame(height: 100)
                    .position(x: geometry.size.width/2, y: geometry.size.height - 50)
                
                SinWave(phase: phase2, strength: 15, frequency: 0.15)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                    .frame(height: 80)
                    .position(x: geometry.size.width/2, y: geometry.size.height - 80)
                
                // Removed the third wave for better performance
            }
            .drawingGroup() // Use Metal acceleration
        }
        .onAppear {
            // Lower animation speeds for better performance
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                phase1 = 2 * .pi
            }
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                phase2 = 2 * .pi
            }
        }
    }
}

// Optimized sin wave with caching
struct SinWave: Shape {
    var phase: Double
    var strength: Double
    var frequency: Double
    
    // Improved path generation with step optimization
    func path(in rect: CGRect) -> Path {
        Path { path in
            let width = rect.width
            let height = rect.height
            let midHeight = height / 2
            
            path.move(to: CGPoint(x: 0, y: midHeight))
            
            // Use larger step size for better performance
            let step: CGFloat = max(1, width / 120) // Limit to 120 line segments
            
            stride(from: 0, through: width, by: step).forEach { x in
                let angle = 2 * .pi * frequency * Double(x) / Double(width) + phase
                let y = midHeight + CGFloat(sin(angle) * strength)
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
    }
    
    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }
}

// Extension to check if audio player is ready
extension AVAudioPlayer {
    var isReady: Bool {
        return duration > 0
    }
}
