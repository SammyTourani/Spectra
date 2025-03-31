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
    @State private var introductionSpeechActive = false // Track if introduction is playing
    @State private var introductionCompleted = false // Track if introduction completed
    @State private var speechCancellationBlocked = false // New flag to prevent introduction speech cancellation
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // MARK: - Background Elements
            NameInputBackground(backgroundGradientAngle: $backgroundGradientAngle)
                .ignoresSafeArea()
            
            EnhancedParticleBackground(isListening: isListening, hasSelectedVoice: hasSelectedVoice)
                .ignoresSafeArea()
            
            // MARK: - Content Layer
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
            
            // MARK: - Overlay Elements
            if isMicrophoneActive {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        EnhancedMicIndicator()
                            .padding(.bottom, 30)
                            .padding(.trailing, 30)
                            .transition(.opacity)
                    }
                }
            }
            
            if isSamplePlaying, let currentSample = currentSample,
               let voiceIndex = voices.firstIndex(where: { $0.0 == currentSample }) {
                EnhancedSamplePlaybackView(voiceText: voices[voiceIndex].2, voiceName: voices[voiceIndex].0)
                    .transition(.opacity)
            }
            
            if hasSelectedVoice, let name = selectedVoiceName {
                ModernSelectionAnimation(voiceName: name)
                    .transition(.opacity)
            }
        }
        .onAppear {
            print("VoiceSelectionView appeared")
            resetViewState()
            prepareAudioSession()
            
            withAnimation {
                isTextVisible = true
            }
            
            initializeView()
            
            withAnimation(Animation.linear(duration: 30).repeatForever(autoreverses: false)) {
                backgroundGradientAngle = 360
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
        speechCancellationBlocked = false // Reset the protection flag
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
        speechCancellationBlocked = true // Block cancellation during introduction
        
        // Cancel any existing speech first to avoid conflicts
        ttsManager.cancelAllSpeech()
        
        // Use speakWithPriority instead of regular speak
        ttsManager.speakWithPriority(
            "Say Amy, Ben, Clara, or Dan to hear me, then 'Select' to choose.",
            voice: self.voices[0].1
        ) {
            print("Introduction speech completed successfully via priority speech")
            self.introductionSpeechActive = false
            self.introductionCompleted = true
            self.speechCancellationBlocked = false // Unblock speech cancellation
            self.animateTitle()
            
            // Add a small buffer to ensure audio playback is fully finished
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.startListening()
            }
        }
        
        // Longer failsafe with a timeout to avoid interrupting priority speech
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if !self.isListening && !self.isSamplePlaying && !self.introductionCompleted {
                print("Failsafe: Starting listening after extended introduction timeout")
                self.introductionSpeechActive = false
                self.introductionCompleted = true
                self.speechCancellationBlocked = false // Unblock speech cancellation
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
        
        // Only cancel speech if we're not in the protected introduction phase
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
        
        // Don't start listening if introduction is still playing or protected
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
        
        // Only cancel speech if we're not in the protected introduction phase
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
            
            // Don't restart listening if speech is protected
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
        
        // Only cancel speech if we're not in the protected introduction phase
        if !speechCancellationBlocked {
            ttsManager.cancelAllSpeech()
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Error activating audio session for sample: \(error)")
            resetAudioSession()
        }
        
        // Set up callback before starting speech to prevent race condition
        let completionHandler = {
            print("Sample finished for \(voice.0), resuming listening")
            self.samplePlaybackFinished()
        }
        
        // Use speakWithPriority instead of regular speak to prevent cancellation
        ttsManager.speakWithPriority(
            voice.2,
            voice: voice.1,
            completion: completionHandler
        )
        
        // More accurate voice-specific timeouts with longer durations for priority speech
        let estimatedDuration = voice.0 == "Dan" ? TimeInterval(6.5) : TimeInterval(6.0)
        
        // First failsafe
        DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration) {
            if self.isSamplePlaying && self.currentSample == voice.0 {
                print("Failsafe 1: Sample may have completed without callback")
                self.samplePlaybackFinished()
            }
        }
        
        // Second failsafe with increased timeout
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
        
        // Start listening with a short delay to ensure complete playback
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
        
        // Only cancel speech if we're not in the protected introduction phase
        if !speechCancellationBlocked {
            ttsManager.cancelAllSpeech()
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            resetAudioSession()
        }
        
        // Use speakWithPriority instead of regular speak
        ttsManager.speakWithPriority(
            "Please say a name first to preview a voice.",
            voice: voices[0].1
        ) {
            self.startListening()
        }
        
        // Longer failsafe for priority speech
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
        
        if let voiceIndex = voices.firstIndex(where: { $0.1 == voice }) {
            selectedVoiceName = voices[voiceIndex].0
        }
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            selectionAnimationActive = true
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        withAnimation {
            isMicrophoneActive = false
        }
        
        // Only cancel speech if we're not in the protected introduction phase
        if !speechCancellationBlocked {
            ttsManager.cancelAllSpeech()
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            resetAudioSession()
        }
        
        // Use speakWithPriority for the selection confirmation
        ttsManager.speakWithPriority(
            "Voice selected. Let's proceed.",
            voice: voice
        ) {
            self.cleanupView()
            print("Voice selection complete - navigating to next screen with voice: \(voice)")
            DispatchQueue.main.async {
                self.onVoiceSelected(voice)
            }
        }
        
        // Longer failsafe for priority speech
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if self.hasSelectedVoice && self.isSamplePlaying {
                print("Navigation failsafe triggered")
                self.cleanupView()
                print("Voice selection complete (failsafe) - navigating to next screen with voice: \(voice)")
                DispatchQueue.main.async {
                    self.onVoiceSelected(voice)
                }
            }
        }
    }
}

// MARK: - Background from NameInputView
struct NameInputBackground: View {
    @Binding var backgroundGradientAngle: Double
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    
    var body: some View {
        GeometryReader { geometry in
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
    }
}

// MARK: - Enhanced Component Views
struct EnhancedParticleBackground: View {
    let isListening: Bool
    let hasSelectedVoice: Bool
    
    let particleCount = 25
    
    var body: some View {
        ZStack {
            ForEach(0..<particleCount, id: \.self) { index in
                EnhancedParticle(
                    index: index,
                    isListening: isListening,
                    hasSelectedVoice: hasSelectedVoice
                )
            }
        }
    }
}

struct EnhancedParticle: View {
    let index: Int
    let isListening: Bool
    let hasSelectedVoice: Bool
    
    @State private var position = CGPoint.zero
    @State private var size: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var isAnimating = false
    @State private var speed: Double = 1.0
    
    var body: some View {
        Circle()
            .fill(Color(red: 180/255, green: 220/255, blue: 255/255))
            .frame(width: size, height: size)
            .opacity(opacity)
            .blur(radius: size * 0.2)
            .position(position)
            .onAppear {
                let screenWidth = UIScreen.main.bounds.width
                let screenHeight = UIScreen.main.bounds.height
                
                position = CGPoint(
                    x: CGFloat.random(in: 0...screenWidth),
                    y: CGFloat.random(in: 0...screenHeight)
                )
                
                size = CGFloat.random(in: 3...8)
                opacity = Double.random(in: 0.1...0.4)
                
                startAnimation()
            }
            .onChange(of: isListening) { newValue in
                updateAnimationState()
            }
            .onChange(of: hasSelectedVoice) { newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        speed = 1.5
                        size = size * 1.3
                        opacity = min(opacity * 1.5, 0.6)
                    }
                } else {
                    updateAnimationState()
                }
            }
    }
    
    private func startAnimation() {
        isAnimating = true
        updateAnimationState()
    }
    
    private func updateAnimationState() {
        if hasSelectedVoice {
            speed = 1.5
        } else if isListening {
            speed = 1.2
        } else {
            speed = 1.0
        }
        
        let duration = Double.random(in: 10...20) / speed
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        withAnimation(Animation.linear(duration: duration).repeatForever(autoreverses: false)) {
            position = CGPoint(
                x: CGFloat.random(in: 0...screenWidth),
                y: CGFloat.random(in: 0...screenHeight)
            )
        }
        
        withAnimation(Animation.easeInOut(duration: Double.random(in: 2...4) / speed).repeatForever(autoreverses: true)) {
            size = CGFloat.random(in: 4...10) * (hasSelectedVoice ? 1.3 : 1.0)
            opacity = Double.random(in: 0.2...0.5) * (hasSelectedVoice ? 1.2 : isListening ? 1.1 : 1.0)
        }
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

struct ModernSelectionAnimation: View {
    let voiceName: String
    
    @State private var outerRingScale: CGFloat = 0.0
    @State private var outerRingOpacity: Double = 0.8
    @State private var innerCircleScale: CGFloat = 0.2
    @State private var checkmarkScale: CGFloat = 0.2
    @State private var textOpacity: Double = 0.0
    @State private var particlesActive: Bool = false
    
    var body: some View {
        ZStack {
            ForEach(0..<20) { i in
                SelectionParticle(active: $particlesActive, index: i)
            }
            
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 120/255, green: 200/255, blue: 255/255),
                            Color(red: 160/255, green: 220/255, blue: 255/255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: 200, height: 200)
                .scaleEffect(outerRingScale)
                .opacity(outerRingOpacity)
            
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 70/255, green: 150/255, blue: 230/255),
                            Color(red: 30/255, green: 80/255, blue: 180/255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .scaleEffect(innerCircleScale)
                .shadow(color: Color(red: 100/255, green: 180/255, blue: 255/255).opacity(0.6), radius: 10)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundColor(.white)
                        .scaleEffect(checkmarkScale)
                )
            
            VStack(spacing: 10) {
                Spacer()
                    .frame(height: 160)
                
                Text("Voice Selected")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(voiceName)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 180/255, green: 240/255, blue: 255/255))
                    .shadow(color: Color(red: 100/255, green: 180/255, blue: 255/255), radius: 5)
            }
            .opacity(textOpacity)
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        withAnimation(Animation.easeOut(duration: 0.6)) {
            outerRingScale = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(Animation.spring(response: 0.5, dampingFraction: 0.7)) {
                innerCircleScale = 1.0
            }
            self.particlesActive = true
            withAnimation(Animation.easeInOut(duration: 1.0)) {
                outerRingOpacity = 0.0
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(Animation.spring(response: 0.3, dampingFraction: 0.6)) {
                checkmarkScale = 1.0
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(Animation.easeIn(duration: 0.4)) {
                textOpacity = 1.0
            }
        }
    }
}

struct SelectionParticle: View {
    @Binding var active: Bool
    let index: Int
    
    @State private var position = CGPoint.zero
    @State private var scale: CGFloat = 0.1
    @State private var opacity: Double = 0.0
    
    var body: some View {
        let size = CGFloat.random(in: 3...10)
        let angle = Double.random(in: 0..<2 * .pi)
        let distance = CGFloat.random(in: 50...180)
        
        Circle()
            .fill(
                Color(
                    red: Double.random(in: 120...200)/255,
                    green: Double.random(in: 180...250)/255,
                    blue: 1.0
                )
            )
            .frame(width: size, height: size)
            .position(position)
            .scaleEffect(scale)
            .opacity(opacity)
            .onChange(of: active) { isActive in
                if isActive {
                    let delay = Double(index) * 0.04
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        let x = sin(angle) * distance
                        let y = cos(angle) * distance
                        withAnimation(Animation.spring(response: 0.5, dampingFraction: 0.7).delay(delay)) {
                            position = CGPoint(x: UIScreen.main.bounds.width/2 + x, y: UIScreen.main.bounds.height/2 - 40 + y)
                            scale = CGFloat.random(in: 0.5...1.0)
                            opacity = Double.random(in: 0.3...0.8)
                        }
                        withAnimation(Animation.easeOut(duration: 0.8).delay(delay + 0.4)) {
                            opacity = 0
                            scale = scale * 1.5
                        }
                    }
                } else {
                    position = CGPoint(x: UIScreen.main.bounds.width/2, y: UIScreen.main.bounds.height/2 - 40)
                    scale = 0.1
                    opacity = 0.0
                }
            }
            .onAppear {
                position = CGPoint(x: UIScreen.main.bounds.width/2, y: UIScreen.main.bounds.height/2 - 40)
            }
    }
}
