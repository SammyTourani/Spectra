import SwiftUI
import AVFoundation

struct NameInputView: View {
    let selectedVoice: String
    let onComplete: (String) -> Void
    
    @StateObject private var speechRecognizers = SpeechRecognizers()
    private let ttsManager = AzureTTSManager.shared
    @StateObject private var audioManager = AudioManager()
    
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
    @State private var hasTriggeredTransition = false
    @State private var audioPlayer: AVAudioPlayer? = nil
    @State private var viewFullyAppeared = false
    @State private var introductionStartTime: Date? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var typingTimer: Timer? = nil
    @State private var sequenceTimer: Timer? = nil
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 46/255, green: 49/255, blue: 146/255),
                        Color(red: 27/255, green: 205/255, blue: 255/255)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ForEach(particles) { particle in
                    Circle()
                        .fill(Color.white)
                        .opacity(particle.opacity)
                        .frame(width: particle.size, height: particle.size)
                        .position(particle.position)
                        .blur(radius: particle.size * 0.2)
                }
                .drawingGroup()
                
                WaveOverlay()
                    .ignoresSafeArea()
                    .opacity(0.2)
                    .drawingGroup()
                
                VStack(spacing: 40) {
                    Text("What's Your Name?")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.2), radius: 2)
                        .padding(.top, 60)
                        .opacity(titleOpacity)
                    
                    Spacer()
                    
                    ZStack {
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
                            ForEach(0..<2) { i in
                                Circle()
                                    .stroke(Color.white.opacity(0.2 - Double(i) * 0.05), lineWidth: 2)
                                    .frame(width: 300 + CGFloat(i * 30), height: 300 + CGFloat(i * 30))
                                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                            }
                            .drawingGroup()
                            
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
                            Text(String(userName.prefix(typingIndex)) + (typingIndex < userName.count ? "|" : ""))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.5), radius: 5)
                        } else if showConfirmation {
                            ZStack {
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
                                    .drawingGroup()
                                
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 220, height: 120)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                                
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
                            VStack(spacing: 20) {
                                Image(systemName: "mic.circle.fill")
                                    .font(.system(size: 70))
                                    .foregroundColor(.white)
                                    .shadow(color: Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.5), radius: 10)
                                
                                Text(introductionStartTime != nil ? "Listening..." : listeningText)
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
            .onChange(of: scenePhase) { newPhase in
                if newPhase != .active {
                    pauseHeavyAnimations()
                } else if newPhase == .active {
                    resumeAnimations()
                }
            }
            .onAppear {
                print("NameInputView: appeared")
                
                initializeAudioPlayer()
                generateParticles(in: geometry.size, count: 15)
                hasTriggeredTransition = false
                
                withAnimation(.easeIn(duration: 1.0)) {
                    titleOpacity = 1
                    containerOpacity = 1
                }
                
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
                
                withAnimation(Animation.linear(duration: 20).repeatForever(autoreverses: false).speed(0.5)) {
                    borderRotation = 360
                }
                
                viewFullyAppeared = true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    runNameIntroductionSequence()
                }
            }
            .onDisappear {
                print("NameInputView: disappeared")
                cleanupResources()
            }
        }
    }
    
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
    
    private func runNameIntroductionSequence() {
        guard viewFullyAppeared && !hasTriggeredTransition else { return }
        
        print("NameInputView: Starting introduction sequence")
        introductionStarted = true
        
        introductionStartTime = Date()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            AudioSessionManager.shared.activate()
            
            print("NameInputView: Playing name introduction")
            self.ttsManager.speak("Please say your name so I can greet you properly.", voice: self.selectedVoice) {
                // No longer primary completion mechanism
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                print("NameInputView: Fixed delay completed, activating microphone")
                AudioSessionManager.shared.resetAndActivate()
                self.startListening()
            }
        }
    }
    
    private func startListening() {
        if hasTriggeredTransition {
            print("NameInputView: Not starting listening, transition already triggered")
            return
        }
        
        isListening = true
        listeningText = "I'm listening..."
        
        speechRecognizers.startRecording { recognizedText in
            if !recognizedText.isEmpty && recognizedText.count > 2 {
                self.speechRecognizers.stopRecording()
                self.isListening = false
                
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
        
        typingInProgress = true
        typingIndex = 0
        
        typingTimer?.invalidate()
        typingTimer = nil
        
        typingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if self.typingIndex < self.userName.count {
                self.typingIndex += 1
                // Commented out until key_press.mp3 is added
                // if let player = self.audioPlayer, player.isReady {
                //     AudioSessionManager.shared.activate()
                //     player.play()
                //     player.currentTime = 0
                //     AudioSessionManager.shared.deactivate()
                // }
            } else {
                timer.invalidate()
                self.typingTimer = nil
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.typingInProgress = false
                    self.showConfirmation = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.nameRevealCompleted = true
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            self.runNameConfirmationSequence()
                        }
                    }
                }
            }
        }
    }
    
    private func runNameConfirmationSequence() {
        guard !greetingPlayed && !hasTriggeredTransition else {
            print("NameInputView: Already played greeting or triggered transition")
            return
        }
        
        print("NameInputView: Running name confirmation sequence for: \(self.userName)")
        
        greetingPlayed = true
        
        AudioSessionManager.shared.activate()
        
        print("NameInputView: Playing greeting")
        let greeting = "Hi \(self.userName)! It's nice to meet you, let's take you to the home menu."
        self.ttsManager.speak(greeting, voice: self.selectedVoice) {
            // Not relying on this completion
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            print("NameInputView: Fixed greeting delay completed, preparing transition")
            self.triggerScreenTransition()
        }
    }
    
    private func triggerScreenTransition() {
        if hasTriggeredTransition {
            print("NameInputView: Transition already triggered, ignoring duplicate")
            return
        }
        
        print("NameInputView: Triggering transition to HomeView")
        
        hasTriggeredTransition = true
        
        ttsManager.cancelAllSpeech()
        AudioSessionManager.shared.deactivate()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("NameInputView: Executing onComplete(\(self.userName))")
            self.onComplete(self.userName)
        }
    }
    
    private func generateParticles(in size: CGSize, count: Int) {
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
                animationDuration: Double.random(in: 20...35)
            )
        }
        
        for i in particles.indices {
            withAnimation(.linear(duration: particles[i].animationDuration).repeatForever(autoreverses: true)) {
                particles[i].position = particles[i].targetPosition
            }
        }
    }
    
    private func pauseHeavyAnimations() {
        typingTimer?.invalidate()
        typingTimer = nil
        sequenceTimer?.invalidate()
        sequenceTimer = nil
    }
    
    private func resumeAnimations() {}
    
    private func cleanupResources() {
        print("NameInputView: Cleaning up resources")
        
        typingTimer?.invalidate()
        typingTimer = nil
        sequenceTimer?.invalidate()
        sequenceTimer = nil
        
        audioPlayer?.stop()
        speechRecognizers.stopRecording()
        ttsManager.cancelAllSpeech()
        AudioSessionManager.shared.deactivate()
    }
}

struct BackgroundParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    let targetPosition: CGPoint
    let size: CGFloat
    let opacity: Double
    let animationDuration: Double
}

struct WaveOverlay: View {
    @State private var phase1: Double = 0
    @State private var phase2: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SinWave(phase: phase1, strength: 20, frequency: 0.1)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                    .frame(height: 100)
                    .position(x: geometry.size.width/2, y: geometry.size.height - 50)
                
                SinWave(phase: phase2, strength: 15, frequency: 0.15)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                    .frame(height: 80)
                    .position(x: geometry.size.width/2, y: geometry.size.height - 80)
            }
            .drawingGroup()
        }
        .onAppear {
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                phase1 = 2 * .pi
            }
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                phase2 = 2 * .pi
            }
        }
    }
}

struct SinWave: Shape {
    var phase: Double
    var strength: Double
    var frequency: Double
    
    func path(in rect: CGRect) -> Path {
        Path { path in
            let width = rect.width
            let height = rect.height
            let midHeight = height / 2
            
            path.move(to: CGPoint(x: 0, y: midHeight))
            
            let step: CGFloat = max(1, width / 120)
            
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

extension AVAudioPlayer {
    var isReady: Bool {
        return duration > 0
    }
}
