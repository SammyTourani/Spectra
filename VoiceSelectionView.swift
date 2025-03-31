import SwiftUI
import AVFoundation
import Speech

struct VoiceSelectionView: View {
    let onVoiceSelected: (String) -> Void
    
    @StateObject private var speechRecognizers = SpeechRecognizers()
    @StateObject private var ttsManager = AzureTTSManager()
    
    @State private var voices = [
        ("Amy", "en-US-AriaNeural", "Hi, I'm Amy—clear and friendly. Say 'Select' to choose me."),
        ("Ben", "en-US-GuyNeural", "I'm Ben—calm and steady. Say 'Select' to pick me."),
        ("Clara", "en-US-JennyNeural", "Hey, I'm Clara—warm and bright. Say 'Select' to join me."),
        ("Dan", "en-US-ChristopherNeural", "I'm Dan—strong and direct. Say 'Select' to activate me.")
    ]
    
    @State private var selectedVoice: String? = nil
    @State private var activeVoice: String? = nil
    @State private var isListening = false
    @State private var wavePhase: Double = 0.0
    @State private var isTextVisible = false
    @State private var viewInitialized = false
    @State private var isSamplePlaying = false
    @State private var currentSample: String? = nil
    @State private var micRestartAttempts = 0
    @State private var lastRecognizedTime: Date = Date()
    @State private var hasSelectedVoice = false // To prevent multiple selections
    @State private var microphoneActive = false // Track microphone active state
    @State private var microphoneOpacity = 0.0  // Smooth fade for microphone
    
    var body: some View {
        ZStack {
            ParticleBackground()
                .ignoresSafeArea()
            
            SineWaveBackground(phase: $wavePhase)
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Text("Choose Your Voice")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2)
                    .opacity(isTextVisible ? 1.0 : 0.0)
                    .animation(.easeIn(duration: 1.0), value: isTextVisible)
                
                VoiceOrbGrid(
                    voices: voices,
                    selectedVoice: $selectedVoice,
                    activeVoice: $activeVoice,
                    onActivate: { voice in playSample(voice: voice) }
                )
                .frame(width: 340, height: 340)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Microphone indicator with smooth fade
            ListeningIndicator(active: microphoneActive)
                .padding(.bottom, 30)
                .padding(.trailing, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .opacity(microphoneOpacity)
                .allowsHitTesting(false) // Prevent interaction with particles
        }
        .onAppear {
            print("VoiceSelectionView appeared")
            isTextVisible = true
            
            // Important: Reset selection state on appear
            hasSelectedVoice = false
            selectedVoice = nil
            activeVoice = nil
            microphoneOpacity = 0.0
            
            withAnimation(Animation.linear(duration: 8).repeatForever(autoreverses: false)) {
                wavePhase = 2 * .pi
            }
            
            // Initialize view with slight delay to ensure proper setup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                initializeView()
            }
        }
        .onDisappear {
            print("VoiceSelectionView disappeared")
            cleanupView()
        }
    }
    
    private func initializeView() {
        // Prevent multiple initializations
        guard !viewInitialized else { return }
        
        print("Initializing voice selection view")
        viewInitialized = true
        
        // Ensure proper sequencing with audio session
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Ensure audio session is properly set up
            self.resetAudioSession()
            
            // Now start the introduction with a slight delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Play introduction message
                self.ttsManager.speak("Say Amy, Ben, Clara, or Dan to hear me, then 'Select' to choose.", voice: self.voices[0].1) {
                    print("Introduction complete, starting listening")
                    self.startListening()
                }
                
                // Failsafe in case TTS completion doesn't trigger
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                    if !self.isListening && !self.isSamplePlaying {
                        print("Failsafe: Starting listening after introduction")
                        self.startListening()
                    }
                }
            }
        }
    }
    
    private func cleanupView() {
        print("Cleaning up view resources")
        speechRecognizers.stopRecording()
        ttsManager.cancelAllSpeech()
        deactivateAudioSession()
        isListening = false
        
        // Smoothly fade out microphone
        withAnimation(.easeOut(duration: 0.3)) {
            microphoneOpacity = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.microphoneActive = false
        }
        
        isSamplePlaying = false
    }
    
    private func resetAudioSession() {
        // Try to deactivate first
        deactivateAudioSession()
        
        // Short delay to let system stabilize
        Thread.sleep(forTimeInterval: 0.1)
        
        // Reactivate session
        AudioSessionManager.shared.activate()
        print("Audio session reset and activated")
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
        
        // Don't restart if we're playing a sample or already selected a voice
        if isSamplePlaying || hasSelectedVoice {
            print("Sample playing or voice already selected, deferring listening")
            return
        }
        
        // First ensure speech recognition is stopped
        speechRecognizers.stopRecording()
        
        // Reset audio session for clean start
        resetAudioSession()
        
        // Update UI state
        isListening = true
        micRestartAttempts = 0
        
        // Start speech recognition with an additional callback for mic state
        speechRecognizers.startRecording(
            onMicStateChange: { active in
                // Update the microphone indicator based on actual state
                self.microphoneActive = active
                
                // Smoothly animate opacity changes
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.microphoneOpacity = active ? 1.0 : 0.0
                }
                
                if active {
                    print("Microphone active - showing indicator")
                } else {
                    print("Microphone inactive - hiding indicator")
                }
            },
            onRecognition: { recognizedText in
                // Update the time stamp for when we last received recognition
                self.lastRecognizedTime = Date()
                
                print("Heard: \(recognizedText)")
                
                // Process voice commands if we're not in a sample and haven't already selected
                if !self.isSamplePlaying && !self.hasSelectedVoice {
                    let lowerText = recognizedText.lowercased()
                    
                    // Fix 1: Process "select" first, before voice names
                    if lowerText.contains("select") {
                        // Process selection command
                        if let selected = self.selectedVoice {
                            print("Select command recognized")
                            self.selectVoice(selected)
                            return
                        } else {
                            self.promptForSelection()
                            return
                        }
                    }
                    
                    // Then process voice names
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
        
        // Restart listening if it stops unexpectedly
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if self.isListening && !self.isSamplePlaying && !self.microphoneActive && !self.hasSelectedVoice {
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
        
        // Complete shutdown
        speechRecognizers.stopRecording()
        ttsManager.cancelAllSpeech()
        deactivateAudioSession()
        
        // Update UI with smooth fade
        withAnimation(.easeOut(duration: 0.3)) {
            microphoneOpacity = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.microphoneActive = false
        }
        
        // Delay for system recovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.resetAudioSession()
            self.micRestartAttempts = 0
            self.isListening = false
            self.isSamplePlaying = false
            
            // Try to restart listening
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startListening()
            }
        }
    }
    
    private func playSample(voice: (String, String, String)) {
        print("Playing sample for \(voice.0)")
        
        // Track which sample we're playing
        currentSample = voice.0
        
        // Update state
        selectedVoice = voice.1
        activeVoice = voice.1
        isListening = false
        
        // Smoothly fade out microphone
        withAnimation(.easeOut(duration: 0.3)) {
            microphoneOpacity = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.microphoneActive = false
        }
        
        isSamplePlaying = true
        
        // Stop current speech recognition
        speechRecognizers.stopRecording()
        
        // Reset audio session for clean playback
        resetAudioSession()
        
        // Play the voice sample
        ttsManager.speak(voice.2, voice: voice.1) {
            print("Sample finished for \(voice.0), resuming listening")
            self.samplePlaybackFinished()
        }
        
        // CRITICAL FIX: Extended time estimates, especially for Dan's voice which might be slower
        // Each voice sample is approximately 5-6 seconds to be safe
        let estimatedDuration = voice.0 == "Dan" ? TimeInterval(7.0) : TimeInterval(6.0)
        
        // Failsafe 1: At estimated duration
        DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration) {
            if self.isSamplePlaying && self.currentSample == voice.0 {
                print("Failsafe 1: Sample may have completed without callback")
                self.samplePlaybackFinished()
            }
        }
        
        // Failsafe 2: Extra buffer time
        DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration + 2.0) {
            if self.isSamplePlaying && self.currentSample == voice.0 {
                print("Failsafe 2: Forcing sample completion")
                self.samplePlaybackFinished()
            }
        }
    }
    
    private func samplePlaybackFinished() {
        // Make sure we only do this once
        guard isSamplePlaying else { return }
        
        print("Sample playback finished, resetting state")
        isSamplePlaying = false
        currentSample = nil
        
        // Resume listening with proper delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Start listening
            self.startListening()
        }
    }
    
    private func promptForSelection() {
        isListening = false
        
        // Smoothly fade out microphone
        withAnimation(.easeOut(duration: 0.3)) {
            microphoneOpacity = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.microphoneActive = false
        }
        
        speechRecognizers.stopRecording()
        
        resetAudioSession()
        ttsManager.speak("Please say a name first to preview a voice.", voice: voices[0].1) {
            self.startListening()
        }
        
        // Failsafe
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if !self.isListening && !self.isSamplePlaying && !self.hasSelectedVoice {
                self.startListening()
            }
        }
    }
    
    private func selectVoice(_ voice: String) {
        // Prevent multiple selections
        if hasSelectedVoice {
            print("Voice already selected, ignoring duplicate selection")
            return
        }
        
        print("Voice selected: \(voice)")
        
        // Mark as selected to prevent multiple selections
        hasSelectedVoice = true
        
        // Update state
        isListening = false
        
        // Smoothly fade out microphone
        withAnimation(.easeOut(duration: 0.3)) {
            microphoneOpacity = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.microphoneActive = false
        }
        
        isSamplePlaying = true // Use this flag to prevent other audio
        speechRecognizers.stopRecording()
        
        // Play confirmation
        resetAudioSession()
        ttsManager.speak("Voice selected. Let's proceed.", voice: voice) {
            // Clean up before proceeding
            self.cleanupView()
            
            print("Voice selection complete - navigating to next screen with voice: \(voice)")
            
            // Use main thread for UI navigation to prevent issues
            DispatchQueue.main.async {
                self.onVoiceSelected(voice)
            }
        }
        
        // Failsafe for navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if self.hasSelectedVoice && self.isSamplePlaying {
                print("Navigation failsafe triggered")
                self.cleanupView()
                
                print("Voice selection complete (failsafe) - navigating to next screen with voice: \(voice)")
                
                // Use main thread for UI navigation
                DispatchQueue.main.async {
                    self.onVoiceSelected(voice)
                }
            }
        }
    }
}

// MARK: - Component Views remain the same

// MARK: - Component Views

struct ParticleBackground: View {
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                ZStack {
                    LinearGradient(
                        gradient: Gradient(colors: [Color(hex: "#2E3192"), Color(hex: "#1BFFFF")]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    ForEach(0..<10) { i in
                        Circle()
                            .fill(Color(hex: "#1BFFFF").opacity(0.4))
                            .frame(width: 8, height: 8)
                            .position(
                                x: geometry.size.width * (0.1 + CGFloat(i) * 0.08) + sin(timeline.date.timeIntervalSince1970 * 2 + Double(i)) * 60,
                                y: geometry.size.height * (0.1 + CGFloat(i) * 0.07) + cos(timeline.date.timeIntervalSince1970 * 1.5 + Double(i)) * 40
                            )
                            .blur(radius: 2)
                    }
                }
            }
        }
    }
}

struct SineWaveBackground: View {
    @Binding var phase: Double
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let width = size.width
                let height = size.height
                let waveHeight: CGFloat = 50
                let frequency: CGFloat = 0.01
                for y in stride(from: 0, through: height, by: 20) {
                    let path = Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        for x in stride(from: 0, through: width, by: 1) {
                            let sineValue = sin(frequency * x + phase + y * 0.02)
                            let offsetY = y + sineValue * waveHeight
                            p.addLine(to: CGPoint(x: x, y: offsetY))
                        }
                    }
                    context.stroke(path, with: .color(Color(hex: "#1BFFFF").opacity(0.1)), lineWidth: 1)
                }
            }
        }
    }
}

struct VoiceOrbGrid: View {
    let voices: [(String, String, String)]
    @Binding var selectedVoice: String?
    @Binding var activeVoice: String?
    let onActivate: ((String, String, String)) -> Void
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: "#1BFFFF").opacity(0.3), lineWidth: 2)
                .frame(width: 300, height: 300)
                .scaleEffect(pulseScale)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulseScale)
                .onAppear { pulseScale = 1.1 }
            
            VStack(spacing: 60) {
                HStack(spacing: 60) {
                    VoiceOrb(
                        voice: voices[0],
                        isSelected: selectedVoice == voices[0].1,
                        isActive: activeVoice == voices[0].1,
                        onActivate: { onActivate(voices[0]) }
                    )
                    VoiceOrb(
                        voice: voices[1],
                        isSelected: selectedVoice == voices[1].1,
                        isActive: activeVoice == voices[1].1,
                        onActivate: { onActivate(voices[1]) }
                    )
                }
                HStack(spacing: 60) {
                    VoiceOrb(
                        voice: voices[2],
                        isSelected: selectedVoice == voices[2].1,
                        isActive: activeVoice == voices[2].1,
                        onActivate: { onActivate(voices[2]) }
                    )
                    VoiceOrb(
                        voice: voices[3],
                        isSelected: selectedVoice == voices[3].1,
                        isActive: activeVoice == voices[3].1,
                        onActivate: { onActivate(voices[3]) }
                    )
                }
            }
        }
    }
}

struct VoiceOrb: View {
    let voice: (String, String, String)
    let isSelected: Bool
    let isActive: Bool
    let onActivate: () -> Void
    
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [Color(hex: "#1BFFFF").opacity(isActive ? 0.5 : isSelected ? 0.3 : 0), .clear]),
                    center: .center,
                    startRadius: 20,
                    endRadius: 60
                ))
                .frame(width: 120, height: 120)
            
            Circle()
                .fill(Color(hex: "#2E3192").opacity(0.8))
                .frame(width: 80, height: 80)
                .overlay(Circle().stroke(Color(hex: "#1BFFFF"), lineWidth: 2))
                .overlay(
                    Text(voice.0)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                )
                .scaleEffect(isActive ? 1.1 : isSelected ? 1.05 : 1.0)
                .opacity(isActive || isSelected ? 1.0 : 0.8)
                .animation(.easeInOut(duration: 0.3), value: isActive || isSelected)
                .shadow(color: Color(hex: "#1BFFFF").opacity(isActive ? 0.5 : 0), radius: 6)
                .onTapGesture(perform: onActivate)
        }
    }
}

struct ListeningIndicator: View {
    let active: Bool
    @State private var pulsePhase: CGFloat = 0.0
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#2E3192").opacity(active ? 0.6 : 0.3))
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .stroke(Color(hex: "#1BFFFF").opacity(active ? 0.8 : 0.4), lineWidth: 2)
                        .scaleEffect(active ? 1.0 + pulsePhase * 0.3 : 1.0)
                        .opacity(active ? 1.0 - pulsePhase : 1.0)
                )
                .shadow(color: Color(hex: "#1BFFFF").opacity(active ? 0.3 : 0), radius: 4)
            
            Image(systemName: "mic.fill")
                .font(.system(size: 16))
                .foregroundColor(.white)
                .scaleEffect(active ? 1.2 : 1.0)
        }
        .animation(.easeInOut(duration: 0.3), value: active)
        .onChange(of: active) { newValue in
            if newValue {
                withAnimation(Animation.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    pulsePhase = 1.0
                }
            } else {
                pulsePhase = 0.0
            }
        }
    }
}
