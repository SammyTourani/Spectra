import SwiftUI
import AVFoundation
import Speech

// MARK: - Main Voice Selection View
struct VoiceSelectionView: View {
    // MARK: - Properties
    let onVoiceSelected: (String) -> Void
    
    // MARK: - State Objects
    @StateObject private var speechRecognizers = SpeechRecognizers()
    @StateObject private var ttsManager = AzureTTSManager.shared
    
    // MARK: - State Variables
    @State private var voices = [
        ("Amy", "en-US-AriaNeural", "Hi, I'm Amy—clear and friendly. Say 'Select' to choose me."),
        ("Ben", "en-US-GuyNeural", "I'm Ben—calm and steady. Say 'Select' to pick me."),
        ("Clara", "en-US-JennyNeural", "Hey, I'm Clara—warm and bright. Say 'Select' to join me."),
        ("Dan", "en-US-ChristopherNeural", "I'm Dan—strong and direct. Say 'Select' to activate me.")
    ]
    
    @State private var selectedVoice: String? = nil
    @State private var activeVoice: String? = nil
    @State private var isListening = false
    @State private var isTextVisible = false
    @State private var viewInitialized = false
    @State private var isSamplePlaying = false
    @State private var currentSample: String? = nil
    @State private var micRestartAttempts = 0
    @State private var lastRecognizedTime: Date = Date()
    @State private var hasSelectedVoice = false
    @State private var isMicrophoneActive = false
    @State private var titleAnimationPhase = 0.0
    @State private var selectionAnimationActive = false
    @State private var selectedVoiceName: String? = nil
    @State private var listeningStarted = false
    @State private var backgroundGradientAngle: Double = 0
    @State private var audioSessionPreActivated = false
    @State private var introductionSpeechActive = false
    @State private var introductionCompleted = false
    @State private var speechCancellationBlocked = false
    @State private var waveOffset: CGFloat = 0
    @State private var particleSystemOpacity: Double = 0
    @State private var backgroundAnimationTime: Double = 0
    @State private var hideUIForSelection: Bool = false
    @State private var mainUIOpacity: Double = 1.0 // For fade effect
    @State private var selectionSpeechFinished: Bool = false
    @State private var animationFinished: Bool = false
    @State private var isNavigating: Bool = false // Prevent multiple navigations
    
    // MARK: - Body
    var body: some View {
        ZStack {
            NeuralNetworkBackground(
                animationTime: $backgroundAnimationTime,
                isListening: isListening,
                hasSelectedVoice: hasSelectedVoice
            )
            .ignoresSafeArea()
            
            FloatingParticleField(
                isListening: isListening,
                hasSelectedVoice: hasSelectedVoice,
                opacity: $particleSystemOpacity
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                AnimatedTitleView(
                    text: "Choose Your Voice",
                    isVisible: isTextVisible,
                    isListeningStarted: listeningStarted
                )
                .padding(.top, 20)
                
                SimpleVoiceGrid(
                    voices: voices,
                    selectedVoice: $selectedVoice,
                    activeVoice: $activeVoice,
                    hasSelectedFinal: hasSelectedVoice,
                    onActivate: { voice in playSample(voice: voice) }
                )
                .frame(width: 340, height: 340)
                .opacity(isTextVisible ? 1.0 : 0.0)
                .animation(.easeIn(duration: 1.0).delay(0.3), value: isTextVisible)
                .scaleEffect(selectionAnimationActive ? 0.95 : 1.0)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: selectionAnimationActive)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(mainUIOpacity)
            
            if isMicrophoneActive {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        EnhancedMicIndicator()
                            .padding(.bottom, 30)
                            .padding(.trailing, 30)
                            .transition(.opacity)
                            .opacity(mainUIOpacity)
                    }
                }
            }
            
            if isSamplePlaying, let currentSample = currentSample,
               let voiceIndex = voices.firstIndex(where: { $0.0 == currentSample }) {
                EnhancedSamplePlaybackView(voiceText: voices[voiceIndex].2, voiceName: voices[voiceIndex].0)
                    .transition(.opacity)
                    .opacity(mainUIOpacity)
            }
            
            if hasSelectedVoice, let name = selectedVoiceName {
                ImprovedSelectionAnimation(
                    voiceName: name,
                    onAnimationComplete: {
                        print("Animation sequence completed")
                        animationFinished = true
                        checkAndNavigate()
                    }
                )
                .transition(.opacity)
            }
        }
        .onAppear {
            print("VoiceSelectionView appeared")
            resetViewState()
            prepareAudioSession()
            
            withAnimation {
                isTextVisible = true
                particleSystemOpacity = 1
            }
            
            initializeView()
            
            withAnimation(Animation.linear(duration: 60).repeatForever(autoreverses: false)) {
                backgroundAnimationTime = 60
            }
        }
        .onDisappear {
            print("VoiceSelectionView disappeared")
            cleanupView()
        }
    }
    
    // MARK: - Helper Methods
    private func resetViewState() {
        isMicrophoneActive = false
        hasSelectedVoice = false
        selectedVoice = nil
        activeVoice = nil
        selectionAnimationActive = false
        titleAnimationPhase = 0.0
        listeningStarted = false
        backgroundGradientAngle = 0
        audioSessionPreActivated = false
        introductionSpeechActive = false
        introductionCompleted = false
        speechCancellationBlocked = false
        particleSystemOpacity = 0
        backgroundAnimationTime = 0
        hideUIForSelection = false
        mainUIOpacity = 1.0
        selectionSpeechFinished = false
        animationFinished = false
        isNavigating = false
    }
    
    private func prepareAudioSession() {
        print("Pre-activating audio session")
        if !audioSessionPreActivated {
            AudioSessionManager.shared.activate()
            audioSessionPreActivated = true
        }
    }
    
    private func initializeView() {
        guard !viewInitialized else { return }
        
        print("Initializing voice selection view")
        viewInitialized = true
        introductionSpeechActive = true
        speechCancellationBlocked = true
        
        ttsManager.cancelAllSpeech()
        
        ttsManager.speakWithPriority(
            "Say Amy, Ben, Clara, or Dan to hear me, then 'Select' to choose.",
            voice: self.voices[0].1
        ) {
            print("Introduction speech completed successfully via priority speech")
            self.introductionSpeechActive = false
            self.introductionCompleted = true
            self.speechCancellationBlocked = false
            self.animateTitle()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.startListening()
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if !self.isListening && !self.isSamplePlaying && !self.introductionCompleted {
                print("Failsafe: Starting listening after extended introduction timeout")
                self.introductionSpeechActive = false
                self.introductionCompleted = true
                self.speechCancellationBlocked = false
                self.animateTitle()
                self.startListening()
            }
        }
    }
    
    private func animateTitle() {
        withAnimation(.spring(response: 1.2, dampingFraction: 0.8, blendDuration: 0.5)) {
            titleAnimationPhase = 1.0
        }
    }
    
    private func cleanupView() {
        print("Cleaning up view resources")
        speechRecognizers.stopRecording()
        
        if !speechCancellationBlocked {
            ttsManager.cancelAllSpeech()
        }
        
        deactivateAudioSession()
        isListening = false
        isSamplePlaying = false
        isMicrophoneActive = false
        introductionSpeechActive = false
    }
    
    private func resetAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            try AVAudioSession.sharedInstance().setActive(true)
            print("Audio session reset efficiently")
        } catch {
            print("Error resetting audio session: \(error)")
            AudioSessionManager.shared.activate()
        }
    }
    
    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("Audio session deactivated")
        } catch {
            print("Error deactivating audio session (ignorable): \(error)")
        }
    }
    
    private func startListening() {
        print("Starting voice command listening")
        
        if introductionSpeechActive || speechCancellationBlocked {
            print("Introduction speech still active or protected, deferring listening")
            return
        }
        
        if isSamplePlaying || hasSelectedVoice {
            print("Sample playing or voice already selected, deferring listening")
            return
        }
        
        speechRecognizers.stopRecording()
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Error activating audio session: \(error)")
            resetAudioSession()
        }
        
        isListening = true
        micRestartAttempts = 0
        listeningStarted = true
        
        speechRecognizers.startRecording(
            onMicStateChange: { active in
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.isMicrophoneActive = active
                }
                print("Microphone active: \(active)")
            },
            onRecognition: { recognizedText in
                self.lastRecognizedTime = Date()
                print("Heard: \(recognizedText)")
                
                if !self.isSamplePlaying && !self.hasSelectedVoice {
                    let lowerText = recognizedText.lowercased()
                    
                    if lowerText.contains("select") {
                        if let selected = self.selectedVoice {
                            print("Select command recognized")
                            self.selectVoice(selected)
                            return
                        } else {
                            self.promptForSelection()
                            return
                        }
                    }
                    
                    if lowerText.contains("amy") {
                        self.playSample(voice: self.voices[0])
                    } else if lowerText.contains("ben") {
                        self.playSample(voice: self.voices[1])
                    } else if lowerText.contains("clara") || lowerText.contains("claire") {
                        self.playSample(voice: self.voices[2])
                    } else if lowerText.contains("dan") {
                        self.playSample(voice: self.voices[3])
                    }
                }
            }
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.isListening && !self.isSamplePlaying && !self.hasSelectedVoice {
                print("Checking if microphone needs restarting")
                self.micRestartAttempts += 1
                if self.micRestartAttempts < 3 {
                    self.startListening()
                } else {
                    print("Too many mic restart attempts, resetting audio system")
                    self.resetAndRestartAudio()
                }
            }
        }
    }
    
    private func resetAndRestartAudio() {
        print("Full audio system reset")
        speechRecognizers.stopRecording()
        
        if !speechCancellationBlocked {
            ttsManager.cancelAllSpeech()
        }
        
        deactivateAudioSession()
        
        withAnimation {
            isMicrophoneActive = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            AudioSessionManager.shared.activate()
            self.micRestartAttempts = 0
            self.isListening = false
            self.isSamplePlaying = false
            
            if !self.speechCancellationBlocked {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.startListening()
                }
            }
        }
    }
    
    private func playSample(voice: (String, String, String)) {
        print("Playing sample for \(voice.0)")
        currentSample = voice.0
        selectedVoice = voice.1
        activeVoice = voice.1
        isListening = false
        isSamplePlaying = true
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        speechRecognizers.stopRecording()
        
        withAnimation {
            isMicrophoneActive = false
        }
        
        if !speechCancellationBlocked {
            ttsManager.cancelAllSpeech()
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Error activating audio session for sample: \(error)")
            resetAudioSession()
        }
        
        let completionHandler = {
            print("Sample finished for \(voice.0), resuming listening")
            self.samplePlaybackFinished()
        }
        
        ttsManager.speakWithPriority(
            voice.2,
            voice: voice.1,
            completion: completionHandler
        )
        
        let estimatedDuration = voice.0 == "Dan" ? TimeInterval(6.5) : TimeInterval(6.0)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration) {
            if self.isSamplePlaying && self.currentSample == voice.0 {
                print("Failsafe 1: Sample may have completed without callback")
                self.samplePlaybackFinished()
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration + 1.5) {
            if self.isSamplePlaying && self.currentSample == voice.0 {
                print("Failsafe 2: Forcing sample completion")
                self.samplePlaybackFinished()
            }
        }
    }
    
    private func samplePlaybackFinished() {
        guard isSamplePlaying else { return }
        
        print("Sample playback finished, resetting state")
        isSamplePlaying = false
        currentSample = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.startListening()
        }
    }
    
    private func promptForSelection() {
        isListening = false
        speechRecognizers.stopRecording()
        
        withAnimation {
            isMicrophoneActive = false
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        
        if !speechCancellationBlocked {
            ttsManager.cancelAllSpeech()
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            resetAudioSession()
        }
        
        ttsManager.speakWithPriority(
            "Please say a name first to preview a voice.",
            voice: voices[0].1
        ) {
            self.startListening()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if !self.isListening && !self.isSamplePlaying && !self.hasSelectedVoice {
                self.startListening()
            }
        }
    }
    
    private func selectVoice(_ voice: String) {
        if hasSelectedVoice {
            print("Voice already selected, ignoring duplicate selection")
            return
        }
        
        print("Voice selected: \(voice)")
        hasSelectedVoice = true
        isListening = false
        isSamplePlaying = true
        speechRecognizers.stopRecording()
        selectionSpeechFinished = false
        animationFinished = false
        
        if let voiceIndex = voices.firstIndex(where: { $0.1 == voice }) {
            selectedVoiceName = voices[voiceIndex].0
        }
        
        withAnimation(.easeOut(duration: 0.5)) {
            mainUIOpacity = 0
        }
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            selectionAnimationActive = true
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        withAnimation {
            isMicrophoneActive = false
        }
        
        if !speechCancellationBlocked {
            ttsManager.cancelAllSpeech()
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            resetAudioSession()
        }
        
        speechCancellationBlocked = true
        print("Speech cancellation blocked for selection confirmation")
        
        let personalizedMessage = getPersonalizedConfirmationMessage(for: selectedVoiceName ?? "")
        print("Starting priority speech for voice selection: \(personalizedMessage)")
        ttsManager.speakWithPriority(
            personalizedMessage,
            voice: voice
        ) {
            print("Selection speech completed successfully via priority callback")
            self.selectionSpeechFinished = true
            self.speechCancellationBlocked = false
            self.checkAndNavigate()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            if self.hasSelectedVoice && !self.selectionSpeechFinished {
                print("Extended speech failsafe triggered after 7 seconds")
                self.selectionSpeechFinished = true
                self.speechCancellationBlocked = false
                self.checkAndNavigate()
            }
        }
    }
    
    private func checkAndNavigate() {
        print("Checking navigation conditions - Speech: \(selectionSpeechFinished), Animation: \(animationFinished)")
        if selectionSpeechFinished && animationFinished && !isNavigating {
            print("Both speech and animation finished - navigating to next screen")
            navigateToNextScreen()
        } else {
            print("Either speech or animation still in progress")
            if !selectionSpeechFinished {
                print("Waiting for speech to complete")
            }
            if !animationFinished {
                print("Waiting for animation to complete")
            }
        }
    }
    
    private func navigateToNextScreen() {
        if isNavigating || selectedVoice == nil {
            print("Navigation already in progress or no voice selected")
            return
        }
        
        isNavigating = true
        print("Voice selection complete - navigating to next screen with voice: \(selectedVoice!)")
        
        speechCancellationBlocked = false
        cleanupView()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.onVoiceSelected(self.selectedVoice!)
        }
    }
    
    private func getPersonalizedConfirmationMessage(for voiceName: String) -> String {
        switch voiceName {
        case "Amy":
            return "Voice selected. I'm Amy, ready to assist you. Let's proceed."
        case "Ben":
            return "Voice selected. I'm Ben, at your service. Let's proceed."
        case "Clara":
            return "Voice selected. I'm Clara, happy to help you. Let's proceed."
        case "Dan":
            return "Voice selected. I'm Dan, your digital assistant. Let's proceed."
        default:
            return "Voice selected. Let's proceed."
        }
    }
}

// MARK: - Neural Network Background
struct NeuralNetworkBackground: View {
    @Binding var animationTime: Double
    let isListening: Bool
    let hasSelectedVoice: Bool
    
    @State private var neuralLines: [NeuralLine] = []
    @State private var isInitialized = false
    
    private let baseColors = [
        Color(red: 10/255, green: 20/255, blue: 50/255),
        Color(red: 15/255, green: 55/255, blue: 115/255),
        Color(red: 20/255, green: 42/255, blue: 92/255)
    ]
    
    private let accentColors = [
        Color(red: 64/255, green: 156/255, blue: 255/255),
        Color(red: 100/255, green: 181/255, blue: 246/255),
        Color(red: 41/255, green: 121/255, blue: 255/255),
        Color(red: 72/255, green: 149/255, blue: 239/255)
    ]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: baseColors),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 30/255, green: 144/255, blue: 255/255).opacity(0.1),
                        Color.black.opacity(0.3)
                    ]),
                    center: .center,
                    startRadius: geometry.size.width * 0.2,
                    endRadius: geometry.size.width
                )
                .ignoresSafeArea()
                
                ForEach(neuralLines) { line in
                    NeuralPathView(
                        line: line,
                        animationTime: animationTime,
                        isListening: isListening,
                        hasSelectedVoice: hasSelectedVoice
                    )
                }
                
                ZStack {
                    RadialGradient(
                        gradient: Gradient(colors: [
                            accentColors[0].opacity(isListening ? 0.3 : 0.15),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 5,
                        endRadius: geometry.size.width * (isListening ? 0.4 : 0.3)
                    )
                    .opacity(hasSelectedVoice ? 0.6 : 1.0)
                    .animation(.easeInOut(duration: 1.5), value: isListening)
                }
            }
            .onAppear {
                if !isInitialized {
                    let screenSize = geometry.size
                    generateNeuralNetwork(size: screenSize)
                    isInitialized = true
                }
            }
            .onChange(of: geometry.size) { newSize in
                let sizeChanged = abs(neuralLines.first?.bounds.width ?? 0 - newSize.width) > 50
                if sizeChanged {
                    generateNeuralNetwork(size: newSize)
                }
            }
        }
    }
    
    private func generateNeuralNetwork(size: CGSize) {
        let nodeCount = 30
        let maxConnections = 4
        var lines: [NeuralLine] = []
        
        var nodePositions: [CGPoint] = []
        for _ in 0..<nodeCount {
            let x = CGFloat.random(in: size.width * 0.05...size.width * 0.95)
            let y = CGFloat.random(in: size.height * 0.05...size.height * 0.95)
            nodePositions.append(CGPoint(x: x, y: y))
        }
        
        for i in 0..<nodeCount {
            let startPoint = nodePositions[i]
            
            var distances: [(index: Int, distance: CGFloat)] = []
            for j in 0..<nodeCount where j != i {
                let endPoint = nodePositions[j]
                let distance = sqrt(pow(endPoint.x - startPoint.x, 2) + pow(endPoint.y - startPoint.y, 2))
                distances.append((j, distance))
            }
            
            distances.sort { $0.distance < $1.distance }
            
            let connectionCount = Int.random(in: 1...min(maxConnections, distances.count))
            for c in 0..<connectionCount {
                let endPoint = nodePositions[distances[c].index]
                
                if !lines.contains(where: {
                    ($0.start == startPoint && $0.end == endPoint) ||
                    ($0.start == endPoint && $0.end == startPoint)
                }) {
                    let line = NeuralLine(
                        id: UUID(),
                        start: startPoint,
                        end: endPoint,
                        color: accentColors.randomElement()!,
                        animationSpeed: Double.random(in: 0.5...2.0),
                        bounds: CGRect(origin: .zero, size: size),
                        pulsePhase: Double.random(in: 0...1)
                    )
                    lines.append(line)
                }
            }
        }
        
        neuralLines = lines
    }
}

struct NeuralLine: Identifiable {
    let id: UUID
    let start: CGPoint
    let end: CGPoint
    let color: Color
    let animationSpeed: Double
    let bounds: CGRect
    let pulsePhase: Double
}

struct NeuralPathView: View {
    let line: NeuralLine
    let animationTime: Double
    let isListening: Bool
    let hasSelectedVoice: Bool
    
    @State private var animationPhase: Double = 0
    
    var body: some View {
        ZStack {
            Path { path in
                path.move(to: line.start)
                path.addLine(to: line.end)
            }
            .stroke(
                line.color.opacity(calculateOpacity()),
                lineWidth: hasSelectedVoice ? 2 : 1
            )
            
            ForEach(0..<(isListening ? 3 : 1), id: \.self) { index in
                Circle()
                    .fill(line.color)
                    .frame(width: 4, height: 4)
                    .position(calculatePulsePosition(phase: Double(index) / 3))
                    .opacity(calculatePulseOpacity(phase: Double(index) / 3))
            }
        }
        .animation(.linear(duration: 0.6), value: isListening)
    }
    
    private func calculateOpacity() -> Double {
        let baseOpacity = hasSelectedVoice ? 0.6 : 0.3
        return baseOpacity + sin(animationTime * line.animationSpeed * 0.5 + line.pulsePhase * 2 * .pi) * 0.15
    }
    
    private func calculatePulsePosition(phase: Double) -> CGPoint {
        let pulsePosition = (animationTime * line.animationSpeed + phase + line.pulsePhase)
            .truncatingRemainder(dividingBy: 1)
        
        let x = line.start.x + (line.end.x - line.start.x) * CGFloat(pulsePosition)
        let y = line.start.y + (line.end.y - line.start.y) * CGFloat(pulsePosition)
        return CGPoint(x: x, y: y)
    }
    
    private func calculatePulseOpacity(phase: Double) -> Double {
        let pulsePosition = (animationTime * line.animationSpeed + phase + line.pulsePhase)
            .truncatingRemainder(dividingBy: 1)
        
        let fadeRange = 0.2
        let opacity: Double
        if pulsePosition < fadeRange {
            opacity = pulsePosition / fadeRange
        } else if pulsePosition > (1 - fadeRange) {
            opacity = (1 - pulsePosition) / fadeRange
        } else {
            opacity = 1.0
        }
        
        return isListening ? opacity * 0.8 : opacity * 0.5
    }
}

struct FloatingParticleField: View {
    let isListening: Bool
    let hasSelectedVoice: Bool
    @Binding var opacity: Double
    
    let particleCount = 35
    
    var body: some View {
        ZStack {
            ForEach(0..<particleCount, id: \.self) { index in
                AdvancedParticle(
                    index: index,
                    isListening: isListening,
                    hasSelectedVoice: hasSelectedVoice,
                    systemOpacity: opacity
                )
            }
        }
    }
}

struct AdvancedParticle: View {
    let index: Int
    let isListening: Bool
    let hasSelectedVoice: Bool
    let systemOpacity: Double
    
    @State private var position = CGPoint.zero
    @State private var size: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var speed: Double = 1.0
    @State private var color: Color = .white
    @State private var shape: ParticleShape = .circle
    @State private var isAnimating = false
    @State private var rotation = 0.0
    
    enum ParticleShape: Int, CaseIterable {
        case circle, square, diamond, star
    }
    
    private let particleColors: [Color] = [
        Color(red: 64/255, green: 156/255, blue: 255/255),
        Color(red: 100/255, green: 181/255, blue: 246/255),
        Color(red: 144/255, green: 202/255, blue: 249/255),
        Color(red: 187/255, green: 222/255, blue: 251/255),
        Color(red: 227/255, green: 242/255, blue: 253/255)
    ]
    
    var body: some View {
        Group {
            switch shape {
            case .circle:
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .blur(radius: size * 0.15)
            case .square:
                RoundedRectangle(cornerRadius: size * 0.2)
                    .fill(color)
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(rotation))
                    .blur(radius: size * 0.1)
            case .diamond:
                Diamond()
                    .fill(color)
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(rotation))
                    .blur(radius: size * 0.1)
            case .star:
                Star(corners: 5, smoothness: 0.45)
                    .fill(color)
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(rotation))
                    .blur(radius: size * 0.15)
            }
        }
        .opacity(opacity * systemOpacity)
        .position(position)
        .onAppear {
            let screenWidth = UIScreen.main.bounds.width
            let screenHeight = UIScreen.main.bounds.height
            
            position = CGPoint(
                x: CGFloat.random(in: 0...screenWidth),
                y: CGFloat.random(in: 0...screenHeight)
            )
            
            size = CGFloat.random(in: 2...8)
            opacity = Double.random(in: 0.1...0.4)
            speed = Double.random(in: 0.7...1.3)
            color = particleColors.randomElement()!
            shape = ParticleShape.allCases.randomElement()!
            rotation = Double.random(in: 0...360)
            
            startAnimation(screenWidth: screenWidth, screenHeight: screenHeight)
        }
        .onChange(of: isListening) { _ in
            updateAnimationState()
        }
        .onChange(of: hasSelectedVoice) { newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.5)) {
                    speed = 1.5
                    size = size * 1.3
                    opacity = min(opacity * 1.5, 0.7)
                }
            } else {
                updateAnimationState()
            }
        }
    }
    
    private func startAnimation(screenWidth: CGFloat, screenHeight: CGFloat) {
        isAnimating = true
        updateAnimationState()
        animatePosition(screenWidth: screenWidth, screenHeight: screenHeight)
    }
    
    private func updateAnimationState() {
        if hasSelectedVoice {
            speed = 1.5
        } else if isListening {
            speed = 1.2
        } else {
            speed = 1.0
        }
        
        if shape != .circle {
            withAnimation(Animation.linear(duration: Double.random(in: 10...20)).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
        
        withAnimation(Animation.easeInOut(duration: Double.random(in: 2...4) / speed).repeatForever(autoreverses: true)) {
            size = CGFloat.random(in: 3...9) * (hasSelectedVoice ? 1.3 : 1.0)
            opacity = Double.random(in: 0.15...0.5) * (hasSelectedVoice ? 1.2 : isListening ? 1.1 : 1.0)
        }
    }
    
    private func animatePosition(screenWidth: CGFloat, screenHeight: CGFloat) {
        let duration = Double.random(in: 10...20) / speed
        
        withAnimation(Animation.linear(duration: duration).repeatForever(autoreverses: false)) {
            position = CGPoint(
                x: CGFloat.random(in: 0...screenWidth),
                y: CGFloat.random(in: 0...screenHeight)
            )
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if self.isAnimating {
                self.animatePosition(screenWidth: screenWidth, screenHeight: screenHeight)
            }
        }
    }
}

// MARK: - Shape Helpers
struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        
        return path
    }
}

struct Star: Shape {
    let corners: Int
    let smoothness: CGFloat
    
    func path(in rect: CGRect) -> Path {
        guard corners >= 2 else { return Path() }
        
        let center = CGPoint(x: rect.width / 2, y: rect.height / 2)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * smoothness
        
        let path = Path { path in
            let angleStep = .pi * 2 / CGFloat(corners)
            
            for corner in 0..<corners {
                let angle = CGFloat(corner) * angleStep - .pi / 2
                let innerAngle = angle + angleStep / 2
                
                let outerPoint = CGPoint(
                    x: center.x + cos(angle) * outerRadius,
                    y: center.y + sin(angle) * outerRadius
                )
                
                let innerPoint = CGPoint(
                    x: center.x + cos(innerAngle) * innerRadius,
                    y: center.y + sin(innerAngle) * innerRadius
                )
                
                if corner == 0 {
                    path.move(to: outerPoint)
                } else {
                    path.addLine(to: outerPoint)
                }
                
                path.addLine(to: innerPoint)
            }
            
            path.closeSubpath()
        }
        
        return path
    }
}

struct EnhancedMicIndicator: View {
    @State private var waveScale: CGFloat = 1.0
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(Color(red: 180/255, green: 220/255, blue: 255/255).opacity(0.7 - Double(i) * 0.2), lineWidth: 2)
                    .frame(width: 50 + CGFloat(i * 15), height: 50 + CGFloat(i * 15))
                    .scaleEffect(waveScale)
                    .opacity((2.0 - waveScale) * 0.5)
            }
            
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 80/255, green: 120/255, blue: 200/255),
                            Color(red: 40/255, green: 60/255, blue: 150/255)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 50)
                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 2))
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(rotation))
                )
                .shadow(color: Color(red: 180/255, green: 220/255, blue: 255/255).opacity(0.5), radius: 8)
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                waveScale = 1.3
            }
            withAnimation(Animation.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                rotation = 5
            }
        }
    }
}

struct EnhancedSamplePlaybackView: View {
    let voiceText: String
    let voiceName: String
    
    @State private var displayedText: String = ""
    @State private var isVisible = false
    @State private var bubbleScale: CGFloat = 0.8
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 80/255, green: 120/255, blue: 200/255),
                                    Color(red: 40/255, green: 60/255, blue: 150/255)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 45, height: 45)
                        .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
                    
                    Text(String(voiceName.prefix(1)))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                .padding(.top, 6)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(voiceName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 180/255, green: 220/255, blue: 255/255))
                    
                    Text(displayedText)
                        .font(.system(size: 18, design: .rounded))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(nil, value: displayedText)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 40/255, green: 60/255, blue: 150/255).opacity(0.8))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.2), lineWidth: 1))
                )
                .padding(.leading, 4)
                .padding(.trailing, 40)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .scaleEffect(bubbleScale)
            .opacity(isVisible ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                isVisible = true
                bubbleScale = 1.0
            }
            displayTextWithTypingAnimation()
        }
    }
    
    private func displayTextWithTypingAnimation() {
        displayedText = ""
        
        let typingSpeed = 0.02
        for i in 0..<voiceText.count {
            let index = voiceText.index(voiceText.startIndex, offsetBy: i)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * typingSpeed) {
                displayedText += String(voiceText[index])
            }
        }
    }
}

struct SimpleVoiceGrid: View {
    let voices: [(String, String, String)]
    @Binding var selectedVoice: String?
    @Binding var activeVoice: String?
    let hasSelectedFinal: Bool
    let onActivate: ((String, String, String)) -> Void
    
    @State private var selectionAnimationCounter = 0
    @State private var orbsVisible = false
    
    var body: some View {
        ZStack {
            PulsatingRing()
            
            VStack(spacing: 60) {
                HStack(spacing: 60) {
                    EnhancedVoiceOrb(
                        voice: voices[0],
                        isSelected: selectedVoice == voices[0].1,
                        isActive: activeVoice == voices[0].1,
                        animationDelay: 0.1,
                        isVisible: orbsVisible,
                        hasSelectedFinal: hasSelectedFinal,
                        selectionAnimationCounter: selectionAnimationCounter,
                        onActivate: { onActivate(voices[0]) }
                    )
                    
                    EnhancedVoiceOrb(
                        voice: voices[1],
                        isSelected: selectedVoice == voices[1].1,
                        isActive: activeVoice == voices[1].1,
                        animationDelay: 0.2,
                        isVisible: orbsVisible,
                        hasSelectedFinal: hasSelectedFinal,
                        selectionAnimationCounter: selectionAnimationCounter,
                        onActivate: { onActivate(voices[1]) }
                    )
                }
                
                HStack(spacing: 60) {
                    EnhancedVoiceOrb(
                        voice: voices[2],
                        isSelected: selectedVoice == voices[2].1,
                        isActive: activeVoice == voices[2].1,
                        animationDelay: 0.3,
                        isVisible: orbsVisible,
                        hasSelectedFinal: hasSelectedFinal,
                        selectionAnimationCounter: selectionAnimationCounter,
                        onActivate: { onActivate(voices[2]) }
                    )
                    
                    EnhancedVoiceOrb(
                        voice: voices[3],
                        isSelected: selectedVoice == voices[3].1,
                        isActive: activeVoice == voices[3].1,
                        animationDelay: 0.4,
                        isVisible: orbsVisible,
                        hasSelectedFinal: hasSelectedFinal,
                        selectionAnimationCounter: selectionAnimationCounter,
                        onActivate: { onActivate(voices[3]) }
                    )
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.6)) {
                    orbsVisible = true
                }
            }
        }
        .onChange(of: hasSelectedFinal) { newValue in
            if newValue {
                animateSelection()
            }
        }
    }
    
    private func animateSelection() {
        for i in 1...5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                self.selectionAnimationCounter += 1
            }
        }
    }
}

struct EnhancedVoiceOrb: View {
    let voice: (String, String, String)
    let isSelected: Bool
    let isActive: Bool
    let animationDelay: Double
    let isVisible: Bool
    let hasSelectedFinal: Bool
    let selectionAnimationCounter: Int
    let onActivate: () -> Void
    
    @State private var isHovered = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationDegrees: Double = 0
    @State private var selectionCounter = 0
    
    var body: some View {
        Button(action: {
            if !hasSelectedFinal {
                onActivate()
            }
        }) {
            ZStack {
                if isActive || isSelected || isHovered {
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 180/255, green: 255/255, blue: 255/255)
                                        .opacity(isActive ? 0.4 : isSelected ? 0.3 : 0.15),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 5,
                                endRadius: 60
                            )
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(hasSelectedFinal ? pulseScale : 1.0)
                }
                
                if isSelected {
                    ZStack {
                        ForEach(0..<2) { i in
                            Circle()
                                .trim(from: 0.4, to: 0.6)
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                                .frame(width: 100, height: 100)
                                .rotationEffect(Angle(degrees: rotationDegrees + Double(i) * 180))
                        }
                    }
                    .onAppear {
                        withAnimation(Animation.linear(duration: 10).repeatForever(autoreverses: false)) {
                            rotationDegrees = 360
                        }
                    }
                }
                
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 65/255, green: 105/255, blue: 225/255).opacity(0.9),
                                Color(red: 30/255, green: 50/255, blue: 120/255).opacity(0.8)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.8),
                                        Color.white.opacity(0.2)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isActive ? 3 : isSelected ? 2 : 1
                            )
                    )
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .blur(radius: 4)
                            .frame(width: 40, height: 40)
                            .offset(x: -15, y: -15)
                    )
                    
                Text(voice.0)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: Color(red: 180/255, green: 255/255, blue: 255/255).opacity(0.8), radius: 2, x: 0, y: 0)
            }
            .scaleEffect(calculateScale())
            .rotation3DEffect(
                isSelected && hasSelectedFinal ? .degrees(Double(selectionCounter) * 3) : .degrees(0),
                axis: (x: 0, y: 1, z: 0)
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .opacity(isVisible ? 1 : 0)
            .blur(radius: hasSelectedFinal && !isSelected ? 1 : 0)
            .animation(.easeInOut(duration: 0.5).delay(animationDelay * 0.7), value: isVisible)
            .onChange(of: selectionAnimationCounter) { newValue in
                if hasSelectedFinal && isSelected {
                    selectionCounter = newValue
                    withAnimation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        pulseScale = 1.2
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func calculateScale() -> CGFloat {
        if hasSelectedFinal {
            return isSelected ? 1.15 : 0.8
        } else {
            return isActive ? 1.1 : isSelected ? 1.05 : isHovered ? 1.02 : 1.0
        }
    }
}

struct AnimatedTitleView: View {
    let text: String
    let isVisible: Bool
    let isListeningStarted: Bool
    
    @State private var displayedText: String = ""
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0
    @State private var isTypingComplete = false
    
    var body: some View {
        Text(displayedText)
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.2), radius: 2)
            .overlay(
                Text(displayedText)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 120/255, green: 200/255, blue: 255/255))
                    .opacity(glowOpacity)
                    .blur(radius: 3)
            )
            .scaleEffect(isListeningStarted && isTypingComplete ? pulseScale : 1.0)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(.easeIn(duration: 0.6), value: isVisible)
            .onChange(of: isVisible) { visible in
                if visible {
                    startTypingAnimation()
                }
            }
            .onChange(of: isListeningStarted) { listening in
                if listening && isTypingComplete {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        pulseScale = 1.05
                        glowOpacity = 0.7
                    }
                }
            }
    }
    
    private func startTypingAnimation() {
        displayedText = ""
        isTypingComplete = false
        
        let typingSpeed = 0.05
        for i in 0..<text.count {
            let index = text.index(text.startIndex, offsetBy: i)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * typingSpeed) {
                displayedText += String(text[index])
                if i == text.count - 1 {
                    isTypingComplete = true
                }
            }
        }
    }
}

struct PulsatingRing: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.8
    
    var body: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white,
                        Color(red: 180/255, green: 220/255, blue: 255/255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2
            )
            .frame(width: 300, height: 300)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                    scale = 1.05
                    opacity = 0.6
                }
            }
    }
}

// MARK: - Improved Selection Animation
struct ImprovedSelectionAnimation: View {
    let voiceName: String
    let onAnimationComplete: () -> Void
    
    @State private var animationStage: AnimationStage = .initial
    @State private var particlesActive: Bool = false
    @State private var circleScale: CGFloat = 0.2
    @State private var contentOpacity: Double = 0.0
    @State private var nameScale: CGFloat = 0.7
    @State private var checkmarkScale: CGFloat = 0.0
    @State private var textOpacity: Double = 0.0
    @State private var circleGlow: Double = 0.0
    
    enum AnimationStage {
        case initial
        case voiceIcon
        case voiceName
        case checkmark
    }
    
    private let accentColor = Color(red: 252/255, green: 186/255, blue: 3/255)
    private let secondaryColor = Color(red: 233/255, green: 30/255, blue: 99/255)
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.5), value: true)
            
            ForEach(0..<30) { i in
                SelectionParticlePro(
                    active: $particlesActive,
                    index: i,
                    accent1: accentColor,
                    accent2: secondaryColor
                )
            }
            
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            accentColor.opacity(0.9),
                            secondaryColor.opacity(0.9),
                            accentColor.opacity(0.7),
                            secondaryColor.opacity(0.7),
                            accentColor.opacity(0.9)
                        ]),
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: 240, height: 240)
                .scaleEffect(animationStage != .initial ? 1.0 : 0.2)
                .opacity(animationStage != .initial ? 0.8 : 0)
            
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                accentColor.opacity(0.9),
                                accentColor.opacity(0.7),
                                accentColor.opacity(0.5)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 70
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 1.5)
                            .blur(radius: 1)
                    )
                    .shadow(color: accentColor.opacity(0.6 + circleGlow * 0.3),
                            radius: 15,
                            x: 0,
                            y: 0)
                
                Group {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 50, weight: .regular))
                        .foregroundColor(.white)
                        .opacity(animationStage == .voiceIcon ? 1 : 0)
                        .scaleEffect(animationStage == .voiceIcon ? 1 : 0.5)
                    
                    Text(voiceName)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .opacity(animationStage == .voiceName ? 1 : 0)
                        .scaleEffect(animationStage == .voiceName ? nameScale : 0.7)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 55, weight: .bold))
                        .foregroundColor(.white)
                        .opacity(animationStage == .checkmark ? 1 : 0)
                        .scaleEffect(animationStage == .checkmark ? checkmarkScale : 0.2)
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: animationStage)
            }
            .frame(width: 120, height: 120)
            .scaleEffect(circleScale)
            
            VStack(spacing: 12) {
                Spacer()
                    .frame(height: 180)
                
                Text("VOICE ACTIVATED")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .kerning(2)
                    .foregroundColor(accentColor)
                
                Text(voiceName)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: accentColor.opacity(0.6), radius: 5)
                
                Text("Ready for conversation")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.8))
                    .padding(.top, 4)
            }
            .opacity(textOpacity)
        }
        .onAppear {
            startAnimationSequence()
        }
    }
    
    private func startAnimationSequence() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            circleScale = 1.0
        }
        
        withAnimation(Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true).delay(0.3)) {
            circleGlow = 0.7
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.particlesActive = true
        }
        
        animationStage = .voiceIcon
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation {
                animationStage = .voiceName
            }
            
            withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                nameScale = 0.9
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation {
                animationStage = .checkmark
            }
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                checkmarkScale = 1.1
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    checkmarkScale = 1.0
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(Animation.easeIn(duration: 0.5)) {
                textOpacity = 1.0
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            print("Animation sequence complete, notifying parent view")
            onAnimationComplete()
        }
    }
}

struct SelectionParticlePro: View {
    @Binding var active: Bool
    let index: Int
    let accent1: Color
    let accent2: Color
    
    @State private var position = CGPoint.zero
    @State private var scale: CGFloat = 0.1
    @State private var opacity: Double = 0.0
    @State private var particleType: ParticleType = .circle
    
    enum ParticleType {
        case circle, square, line
    }
    
    var body: some View {
        Group {
            switch particleType {
            case .circle:
                Circle()
                    .fill(index % 2 == 0 ? accent1 : accent2)
                    .frame(width: scale * 10, height: scale * 10)
            case .square:
                Rectangle()
                    .fill(index % 2 == 0 ? accent1 : accent2)
                    .frame(width: scale * 8, height: scale * 8)
                    .rotationEffect(Angle(degrees: Double(index) * 10))
            case .line:
                RoundedRectangle(cornerRadius: 1)
                    .fill(index % 2 == 0 ? accent1 : accent2)
                    .frame(width: 1, height: scale * 15)
                    .rotationEffect(Angle(degrees: Double(index) * 10))
            }
        }
        .position(position)
        .opacity(opacity)
        .onChange(of: active) { isActive in
            if isActive {
                let delay = Double(index) * 0.03
                
                particleType = [ParticleType.circle, .square, .line].randomElement()!
                
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    let distance = CGFloat.random(in: 80...230)
                    let angle = Double.random(in: 0..<2 * .pi)
                    
                    let x = sin(angle) * distance
                    let y = cos(angle) * distance
                    
                    withAnimation(Animation.spring(response: 0.6, dampingFraction: 0.7).delay(delay)) {
                        position = CGPoint(
                            x: UIScreen.main.bounds.width/2 + x,
                            y: UIScreen.main.bounds.height/2 - 40 + y
                        )
                        scale = CGFloat.random(in: 0.6...1.5)
                        opacity = Double.random(in: 0.4...0.9)
                    }
                    
                    withAnimation(Animation.easeOut(duration: 1.2).delay(delay + 0.6)) {
                        opacity = 0
                        scale = scale * 1.8
                    }
                }
            } else {
                position = CGPoint(x: UIScreen.main.bounds.width/2, y: UIScreen.main.bounds.height/2 - 40)
                scale = 0.1
                opacity = 0
            }
        }
        .onAppear {
            position = CGPoint(x: UIScreen.main.bounds.width/2, y: UIScreen.main.bounds.height/2 - 40)
        }
    }
}
