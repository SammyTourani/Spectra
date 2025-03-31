import SwiftUI
import AVFoundation

struct NameInputView: View {
    // MARK: - Properties
    let selectedVoice: String
    let onComplete: (String) -> Void
    
    // MARK: - State Objects
    @StateObject private var speechRecognizers = SpeechRecognizers()
    private let ttsManager = AzureTTSManager.shared
    @StateObject private var audioManager = AudioManager()
    
    // MARK: - UI State
    @State private var userName: String = ""
    @State private var isListening: Bool = false
    @State private var listeningText: String = "Say your name..."
    @State private var typingIndex: Int = 0
    @State private var typingInProgress: Bool = false
    @State private var showConfirmation: Bool = false
    @State private var greetingPlayed: Bool = false
    
    // MARK: - Animation States
    @State private var pulseAnimation: Bool = false
    @State private var particles: [AnimatedParticle] = []
    @State private var floatingOrbs: [FloatingOrb] = []
    @State private var titleOpacity: Double = 0
    @State private var containerOpacity: Double = 0
    @State private var borderRotation: Double = 0
    @State private var introductionStarted = false
    @State private var nameRevealCompleted = false
    @State private var hasTriggeredTransition = false
    @State private var microphonePulse: Bool = false
    @State private var waveAmplitude: CGFloat = 0
    @State private var waveFade: Double = 0
    
    // MARK: - Progress States
    @State private var viewFullyAppeared = false
    @State private var introductionStartTime: Date? = nil
    @State private var nameHintOpacity: Double = 0
    @State private var backgroundGradientAngle: Double = 0
    
    // MARK: - Environment and Timers
    @Environment(\.scenePhase) private var scenePhase
    @State private var typingTimer: Timer? = nil
    @State private var sequenceTimer: Timer? = nil
    @State private var audioPlayer: AVAudioPlayer? = nil
    @State private var visualizerTimer: Timer? = nil
    @State private var audioVisualizerValues: [CGFloat] = Array(repeating: 0, count: 20)
    
    // MARK: - Accessibility
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundLayer(geometry: geometry)
                particlesLayer(geometry: geometry)
                waveOverlayLayer()
                    .opacity(waveFade)
                    .animation(.easeInOut(duration: 2.0), value: waveFade)
                
                VStack(spacing: 40) {
                    titleView()
                        .padding(.top, 60)
                    Spacer()
                    ZStack {
                        circleContainer()
                        if isListening {
                            listeningStateView()
                        } else if typingInProgress {
                            typingStateView()
                        } else if showConfirmation {
                            confirmationStateView()
                        } else {
                            initialStateView()
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
                initializeView(geometry: geometry)
            }
            .onDisappear {
                print("NameInputView: disappeared")
                cleanupResources()
            }
        }
    }
    
    private func backgroundLayer(geometry: GeometryProxy) -> some View {
        ZStack {
            AngularGradient(
                gradient: Gradient(colors: [
                    Color(red: 46/255, green: 49/255, blue: 146/255),
                    Color(red: 27/255, green: 205/255, blue: 255/255),
                    Color(red: 38/255, green: 120/255, blue: 190/255),
                    Color(red: 46/255, green: 49/255, blue: 146/255)
                ]),
                center: .center,
                angle: .degrees(backgroundGradientAngle)
            )
            .ignoresSafeArea()
            
            Color.white.opacity(0.03)
                .ignoresSafeArea()
                .blendMode(.overlay)
            
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(reduceTransparency ? 0.2 : 0.3)
                ]),
                center: .center,
                startRadius: geometry.size.width * 0.3,
                endRadius: geometry.size.width * 0.7
            )
            .ignoresSafeArea()
            .blendMode(.multiply)
        }
    }
    
    private func particlesLayer(geometry: GeometryProxy) -> some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.7),
                                Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.6)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: particle.size, height: particle.size)
                    .position(particle.position)
                    .opacity(particle.opacity)
                    .blur(radius: particle.size * 0.3)
            }
            
            ForEach(floatingOrbs) { orb in
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color(hue: orb.hue, saturation: 0.7, brightness: 0.9).opacity(0.8),
                                    Color(hue: orb.hue, saturation: 0.8, brightness: 1.0).opacity(0.3),
                                    Color(hue: orb.hue, saturation: 0.6, brightness: 0.8).opacity(0)
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: orb.size
                            )
                        )
                        .frame(width: orb.size * 2, height: orb.size * 2)
                        .position(orb.position)
                        .blendMode(.screen)
                }
            }
        }
        .drawingGroup()
        .opacity(reduceMotion ? 0.5 : 1.0)
    }
    
    private func waveOverlayLayer() -> some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<3) { index in
                    EnhancedWaveView(
                        amplitude: waveAmplitude * (1.0 - Double(index) * 0.2),
                        frequency: 0.1 + Double(index) * 0.05,
                        phase: Double(index) * 1.5,
                        horizontalOffset: CGFloat(index) * 10
                    )
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.1 + Double(index) * 0.1),
                                Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.2 + Double(index) * 0.1),
                                Color.white.opacity(0.1 + Double(index) * 0.1)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 2 - CGFloat(index) * 0.5
                    )
                    .frame(height: 100 - CGFloat(index) * 20)
                    .position(
                        x: geometry.size.width/2,
                        y: geometry.size.height - CGFloat(100 - index * 30)
                    )
                    .blur(radius: CGFloat(index))
                }
            }
            .drawingGroup()
        }
    }
    
    private func titleView() -> some View {
        VStack(spacing: 12) {
            Text("What's Your Name?")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.7), radius: 15, x: 0, y: 0)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
                .opacity(titleOpacity)
                .offset(y: titleOpacity * 10 - 10) // Add vertical movement during fade-in
            
            Text("Let me learn who you are")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                .opacity(titleOpacity * 0.8)
                .offset(y: titleOpacity * 8 - 8) // Slightly different offset for staggered effect
                .blur(radius: (1 - titleOpacity) * 5) // Blur effect that clears as opacity increases
        }
        .drawingGroup()
    }
    
    private func circleContainer() -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.06)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 140
                    )
                )
                .frame(width: 280, height: 280)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.8),
                                    Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.6),
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.6)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.3), radius: 30, x: 0, y: 0)
                .opacity(containerOpacity)
            
            ForEach(0..<3) { index in
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.1),
                                Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.7),
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1)
                            ]),
                            center: .center,
                            startAngle: .degrees(Double(index) * 120),
                            endAngle: .degrees(Double(index) * 120 + 360)
                        ),
                        lineWidth: 1.5 - CGFloat(index) * 0.3
                    )
                    .frame(width: 300 + CGFloat(index * 20), height: 300 + CGFloat(index * 20))
                    .rotationEffect(.degrees(borderRotation * (index % 2 == 0 ? 1 : -1)))
                    .opacity(containerOpacity * (1.0 - Double(index) * 0.2))
                    .blur(radius: CGFloat(index))
            }
        }
        .drawingGroup()
    }
    
    private func listeningStateView() -> some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.3 - Double(i) * 0.1),
                                Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.4 - Double(i) * 0.1),
                                Color.white.opacity(0.3 - Double(i) * 0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2 - CGFloat(i) * 0.5
                    )
                    .frame(width: 300 + CGFloat(i * 30), height: 300 + CGFloat(i * 30))
                    .scaleEffect(microphonePulse ? 1.15 - CGFloat(i) * 0.05 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 1.2)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.2),
                        value: microphonePulse
                    )
            }
            
            VStack(spacing: 25) {
                HStack(spacing: 4) {
                    ForEach(0..<audioVisualizerValues.count, id: \.self) { index in
                        AudioBar(height: audioVisualizerValues[index])
                            .animation(
                                .spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.3),
                                value: audioVisualizerValues[index]
                            )
                    }
                }
                .frame(width: 180, height: 60)
                .padding(.bottom, 5)
                
                ZStack {
                    Circle()
                        .fill(Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.6))
                        .frame(width: 80, height: 80)
                        .blur(radius: 15)
                        .opacity(microphonePulse ? 0.8 : 0.4)
                        .animation(
                            Animation.easeInOut(duration: 1.0)
                                .repeatForever(autoreverses: true),
                            value: microphonePulse
                        )
                    
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 70, weight: .regular))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .white,
                                    Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.9)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.7), radius: 10, x: 0, y: 0)
                }
                
                Text(listeningText)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 3)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.white.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .blur(radius: 0.5)
                    )
            }
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.9)),
                    removal: .opacity.combined(with: .scale(scale: 1.1))
                )
            )
        }
    }
    
    private func typingStateView() -> some View {
        ZStack {
            // Character-by-character fade in with cursor
            HStack(spacing: 0) {
                ForEach(0..<min(typingIndex, userName.count), id: \.self) { index in
                    let character = String(userName[userName.index(userName.startIndex, offsetBy: index)])
                    Text(character)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .white,
                                    Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.9)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.5), radius: 10, x: 0, y: 0)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
                        .transition(.scale.combined(with: .opacity))
                        .id("char\(index)")
                }
                
                // Animated cursor
                if typingIndex < userName.count {
                    Text("|")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .opacity(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1.0) < 0.5 ? 1 : 0)
                        .animation(.easeInOut(duration: 0.5), value: Date().timeIntervalSince1970)
                }
            }
            .padding(.horizontal, 30)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: 280)
        }
    }
    
    private func confirmationStateView() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 27/255, green: 205/255, blue: 255/255),
                            Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.7),
                            Color(red: 46/255, green: 49/255, blue: 146/255).opacity(0.8),
                            Color.white.opacity(0.9),
                            Color(red: 27/255, green: 205/255, blue: 255/255)
                        ]),
                        center: .center,
                        startAngle: .degrees(borderRotation),
                        endAngle: .degrees(borderRotation + 360)
                    ),
                    lineWidth: 3
                )
                .frame(width: 240, height: 160)
                .shadow(color: Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.5), radius: 15, x: 0, y: 0)
                .opacity(0.8)
            
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.15))
                .frame(width: 230, height: 150)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .blur(radius: 0.5)
            
            VStack(spacing: greetingPlayed ? 18 : 0) {
                Text(userName)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 27/255, green: 205/255, blue: 255/255),
                                .white,
                                Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.8)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.7), radius: 10, x: 0, y: 0)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
                    .padding(.horizontal, 20)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                if greetingPlayed {
                    Text("Nice to meet you!")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                                )
                        )
                        .opacity(greetingPlayed ? 1 : 0)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .opacity(nameRevealCompleted ? 1 : 0)
            .animation(.easeIn(duration: 0.8), value: nameRevealCompleted)
        }
    }
    
    private func initialStateView() -> some View {
        ZStack {
            VStack(spacing: 25) {
                ZStack {
                    Circle()
                        .fill(Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.3))
                        .frame(width: 80, height: 80)
                        .blur(radius: 15)
                        .opacity(pulseAnimation ? 0.7 : 0.3)
                        .animation(
                            Animation.easeInOut(duration: 2.0)
                                .repeatForever(autoreverses: true),
                            value: pulseAnimation
                        )
                    
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 70, weight: .regular))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .white,
                                    Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.9)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.5), radius: 8, x: 0, y: 0)
                }
                
                Text(introductionStartTime != nil ? "Listening..." : listeningText)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 3)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.white.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .blur(radius: 0.5)
                    )
                
                Text("Tap the mic to begin")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .shadow(color: .black.opacity(0.3), radius: 1)
                    .opacity(nameHintOpacity)
                    .padding(.top, 10)
            }
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.9)),
                    removal: .opacity.combined(with: .scale(scale: 1.1))
                )
            )
            .opacity(introductionStarted ? 1 : 0)
        }
    }
    
    private func initializeView(geometry: GeometryProxy) {
        initializeAudioPlayer()
        generateParticles(in: geometry.size, count: 20)
        generateFloatingOrbs(in: geometry.size, count: 6)
        
        hasTriggeredTransition = false
        
        withAnimation(.easeIn(duration: 1.0)) {
            titleOpacity = 1
            containerOpacity = 1
        }
        
        withAnimation(.easeInOut(duration: 1.0).delay(0.5)) {
            waveFade = 0.2
            waveAmplitude = 20
        }
        
        withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseAnimation = true
            microphonePulse = true
        }
        
        withAnimation(Animation.linear(duration: 20).repeatForever(autoreverses: false)) {
            borderRotation = 360
        }
        
        withAnimation(Animation.linear(duration: 30).repeatForever(autoreverses: false)) {
            backgroundGradientAngle = 360
        }
        
        startAudioVisualizerSimulation()
        
        viewFullyAppeared = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeIn(duration: 0.8)) {
                nameHintOpacity = 0.7
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            runNameIntroductionSequence()
        }
    }
    
    private func generateParticles(in size: CGSize, count: Int) {
        particles = (0..<count).map { _ in
            let position = CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height)
            )
            return AnimatedParticle(
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
    
    private func generateFloatingOrbs(in size: CGSize, count: Int) {
        floatingOrbs = (0..<count).map { _ in
            let position = CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height)
            )
            return FloatingOrb(
                position: position,
                targetPosition: CGPoint(
                    x: position.x + CGFloat.random(in: -100...100),
                    y: position.y + CGFloat.random(in: -100...100)
                ),
                size: CGFloat.random(in: 15...40),
                hue: Double.random(in: 0.5...0.7),
                animationDuration: Double.random(in: 25...45)
            )
        }
        
        for i in floatingOrbs.indices {
            withAnimation(.linear(duration: floatingOrbs[i].animationDuration).repeatForever(autoreverses: true)) {
                floatingOrbs[i].position = floatingOrbs[i].targetPosition
            }
        }
    }
    
    private func startAudioVisualizerSimulation() {
        visualizerTimer?.invalidate()
        visualizerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            for i in 0..<self.audioVisualizerValues.count {
                if i % 4 == 0 {
                    self.audioVisualizerValues[i] = CGFloat.random(in: isListening ? 10...40 : 0...15)
                } else {
                    let neighborIndex = i - (i % 4)
                    let neighborValue = self.audioVisualizerValues[neighborIndex]
                    self.audioVisualizerValues[i] = max(0, neighborValue + CGFloat.random(in: -10...10))
                }
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
                if let player = self.audioPlayer, player.duration > 0 {
                    AudioSessionManager.shared.activate()
                    player.play()
                    player.currentTime = 0
                    AudioSessionManager.shared.deactivate()
                }
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
        
        withAnimation(.easeInOut(duration: 0.8)) {
            titleOpacity = 0
            containerOpacity = 0
            waveFade = 0
        }
        
        ttsManager.cancelAllSpeech()
        AudioSessionManager.shared.deactivate()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("NameInputView: Executing onComplete(\(self.userName))")
            self.onComplete(self.userName)
        }
    }
    
    private func pauseHeavyAnimations() {
        typingTimer?.invalidate()
        typingTimer = nil
        sequenceTimer?.invalidate()
        sequenceTimer = nil
        visualizerTimer?.invalidate()
        visualizerTimer = nil
    }
    
    private func resumeAnimations() {
        if isListening {
            startAudioVisualizerSimulation()
        }
    }
    
    private func cleanupResources() {
        print("NameInputView: Cleaning up resources")
        
        typingTimer?.invalidate()
        typingTimer = nil
        sequenceTimer?.invalidate()
        sequenceTimer = nil
        visualizerTimer?.invalidate()
        visualizerTimer = nil
        
        audioPlayer?.stop()
        speechRecognizers.stopRecording()
        ttsManager.cancelAllSpeech()
        AudioSessionManager.shared.deactivate()
    }
}

struct AnimatedParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    let targetPosition: CGPoint
    let size: CGFloat
    let opacity: Double
    let animationDuration: Double
}

struct FloatingOrb: Identifiable {
    let id = UUID()
    var position: CGPoint
    let targetPosition: CGPoint
    let size: CGFloat
    let hue: Double
    let animationDuration: Double
}

struct EnhancedWaveView: Shape {
    var amplitude: CGFloat
    var frequency: Double
    var phase: Double
    var horizontalOffset: CGFloat = 0
    
    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        Path { path in
            let width = rect.width + horizontalOffset * 2
            let height = rect.height
            let midHeight = height / 2
            
            path.move(to: CGPoint(x: -horizontalOffset, y: midHeight))
            
            let step: CGFloat = 1
            
            for x in stride(from: -horizontalOffset, through: width - horizontalOffset, by: step) {
                let relativeX = x + horizontalOffset
                let angle = 2 * .pi * frequency * Double(relativeX) / Double(width) + phase
                let y = midHeight + CGFloat(sin(angle) * Double(amplitude))
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
    }
}

struct AudioBar: View {
    var height: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.7),
                        Color(red: 27/255, green: 205/255, blue: 255/255)
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 4, height: height)
            .shadow(color: Color(red: 27/255, green: 205/255, blue: 255/255).opacity(0.5), radius: 2)
    }
}

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    
    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = sin(animatableData * .pi * 2) * 5
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

struct ConfettiView: View {
    @State private var confettiPieces: [ConfettiPiece] = []
    
    var body: some View {
        ZStack {
            ForEach(confettiPieces) { piece in
                ConfettiPieceView(piece: piece)
            }
        }
        .onAppear {
            createConfetti()
        }
    }
    
    private func createConfetti() {
        for _ in 0..<100 {
            confettiPieces.append(ConfettiPiece())
        }
    }
}

struct ConfettiPiece: Identifiable {
    let id = UUID()
    let position: CGPoint
    let rotation: Double
    let color: Color
    let size: CGFloat
    let animationDelay: Double
    
    init() {
        position = CGPoint(
            x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
            y: -50
        )
        
        rotation = Double.random(in: 0...360)
        
        let colors: [Color] = [.blue, .red, .green, .yellow, .orange, .purple, .pink]
        color = colors.randomElement()!
        
        size = CGFloat.random(in: 5...12)
        
        animationDelay = Double.random(in: 0...1.0)
    }
}

struct ConfettiPieceView: View {
    let piece: ConfettiPiece
    
    @State private var yPosition: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var opacity: Double = 0
    
    var body: some View {
        Rectangle()
            .fill(piece.color)
            .frame(width: piece.size, height: piece.size * 3)
            .position(x: piece.position.x, y: piece.position.y + yPosition)
            .rotationEffect(. degrees(rotation))
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    Animation
                        .easeOut(duration: 3)
                        .delay(piece.animationDelay)
                ) {
                    yPosition = UIScreen.main.bounds.height + 100
                    rotation = piece.rotation + Double.random(in: 180...540)
                    
                    withAnimation(
                        Animation
                            .easeIn(duration: 0.3)
                            .delay(piece.animationDelay)
                    ) {
                        opacity = 0.7
                    }
                    
                    withAnimation(
                        Animation
                            .easeInOut(duration: 1.0)
                            .delay(piece.animationDelay + 2.0)
                    ) {
                        opacity = 0
                    }
                }
            }
    }
}

extension AVAudioPlayer {
    var isReady: Bool {
        return duration > 0
    }
}
