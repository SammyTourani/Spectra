import SwiftUI
import AVFoundation
import Speech

// MARK: - Main Voice Selection View

struct VoiceSelectionView: View {
    // MARK: - Properties
    
    /// Callback triggered when a voice is selected to proceed to next screen
    let onVoiceSelected: (String) -> Void
    
    // MARK: - State Objects
    
    /// Speech recognition manager
    @StateObject private var speechRecognizers = SpeechRecognizers()
    
    /// Text-to-speech manager for voice playback
    @StateObject private var ttsManager = AzureTTSManager.shared
    
    // MARK: - State Variables
    
    /// Available voice options with display name, voice ID, and sample text
    @State private var voices = [
        ("Amy", "en-US-AriaNeural", "Hi, I'm Amy—clear and friendly. Say 'Select' to choose me."),
        ("Ben", "en-US-GuyNeural", "I'm Ben—calm and steady. Say 'Select' to pick me."),
        ("Clara", "en-US-JennyNeural", "Hey, I'm Clara—warm and bright. Say 'Select' to join me."),
        ("Dan", "en-US-ChristopherNeural", "I'm Dan—strong and direct. Say 'Select' to activate me.")
    ]
    
    /// Voice ID of the currently selected voice
    @State private var selectedVoice: String? = nil
    
    /// Voice ID of the voice being previewed
    @State private var activeVoice: String? = nil
    
    /// Whether speech recognition is active
    @State private var isListening = false
    
    /// Controls visibility of UI text elements
    @State private var isTextVisible = false
    
    /// Tracks if view setup has completed
    @State private var viewInitialized = false
    
    /// Whether a voice sample is currently playing
    @State private var isSamplePlaying = false
    
    /// Name of the currently playing voice sample
    @State private var currentSample: String? = nil
    
    /// Counter for microphone restart attempts
    @State private var micRestartAttempts = 0
    
    /// Time of last voice recognition
    @State private var lastRecognizedTime: Date = Date()
    
    /// Whether a voice has been chosen (prevents multiple selections)
    @State private var hasSelectedVoice = false
    
    /// Tracks actual microphone activity for UI feedback
    @State private var isMicrophoneActive = false
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // MARK: - Background Elements
            
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 46/255, green: 49/255, blue: 146/255),
                    Color(red: 20/255, green: 30/255, blue: 90/255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Simple animated particles
            SimpleParticleBackground()
                .ignoresSafeArea()
            
            // MARK: - Content Layer
            
            VStack(spacing: 40) {
                // Title with gradient
                Text("Choose Your Voice")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 3)
                    .opacity(isTextVisible ? 1.0 : 0.0)
                    .animation(.easeIn(duration: 1.0), value: isTextVisible)
                
                // Voice selection grid
                SimpleVoiceGrid(
                    voices: voices,
                    selectedVoice: $selectedVoice,
                    activeVoice: $activeVoice,
                    onActivate: { voice in playSample(voice: voice) }
                )
                .frame(width: 340, height: 340)
                .opacity(isTextVisible ? 1.0 : 0.0)
                .animation(.easeIn(duration: 1.0).delay(0.3), value: isTextVisible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // MARK: - Overlay Elements
            
            // Microphone indicator
            if isMicrophoneActive {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        SimpleMicIndicator()
                            .padding(.bottom, 30)
                            .padding(.trailing, 30)
                            .transition(.opacity)
                    }
                }
            }
            
            // Sample playback overlay
            if isSamplePlaying, let currentSample = currentSample,
               let voiceIndex = voices.firstIndex(where: { $0.0 == currentSample }) {
                SamplePlaybackView(voiceText: voices[voiceIndex].2)
                    .transition(.opacity)
            }
        }
        .onAppear {
            print("VoiceSelectionView appeared")
            resetViewState()
            
            // Show UI elements with animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextVisible = true
            }
            
            // Initialize view with slight delay for proper setup
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                initializeView()
            }
        }
        .onDisappear {
            print("VoiceSelectionView disappeared")
            cleanupView()
        }
    }
    
    // MARK: - Helper Methods
    
    /// Resets all view state on appear
    private func resetViewState() {
        isMicrophoneActive = false
        
        // Reset selection states
        hasSelectedVoice = false
        selectedVoice = nil
        activeVoice = nil
    }
    
    /// Initializes speech recognition and TTS
    private func initializeView() {
        // Prevent multiple initializations
        guard !viewInitialized else { return }
        
        print("Initializing voice selection view")
        viewInitialized = true
        
        // Ensure proper sequencing with audio session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            // Ensure audio session is properly set up
            self.resetAudioSession()
            
            // Start the introduction with slight delay
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
    
    /// Releases resources on view dismissal
    private func cleanupView() {
        print("Cleaning up view resources")
        speechRecognizers.stopRecording()
        ttsManager.cancelAllSpeech()
        deactivateAudioSession()
        isListening = false
        isSamplePlaying = false
        isMicrophoneActive = false
    }
    
    /// Resets the audio session to ensure clean state
    private func resetAudioSession() {
        // Try to deactivate first
        deactivateAudioSession()
        
        // Short delay to let system stabilize
        Thread.sleep(forTimeInterval: 0.1)
        
        // Reactivate session
        AudioSessionManager.shared.activate()
        print("Audio session reset and activated")
    }
    
    /// Deactivates the audio session
    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("Audio session deactivated")
        } catch {
            print("Error deactivating audio session (ignorable): \(error)")
        }
    }
    
    /// Starts voice recognition
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
        
        // Start speech recognition with mic state tracking
        speechRecognizers.startRecording(
            onMicStateChange: { active in
                // Update microphone state with animation
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.isMicrophoneActive = active
                }
                print("Microphone active: \(active)")
            },
            onRecognition: { recognizedText in
                // Update the time stamp for when we last received recognition
                self.lastRecognizedTime = Date()
                
                print("Heard: \(recognizedText)")
                
                // Process voice commands if we're not in a sample and haven't already selected
                if !self.isSamplePlaying && !self.hasSelectedVoice {
                    let lowerText = recognizedText.lowercased()
                    
                    // Process "select" first, before voice names
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
    
    /// Performs a full reset of the audio system when issues are detected
    private func resetAndRestartAudio() {
        print("Full audio system reset")
        
        // Complete shutdown
        speechRecognizers.stopRecording()
        ttsManager.cancelAllSpeech()
        deactivateAudioSession()
        
        // Update UI state - microphone is definitely off now
        withAnimation {
            isMicrophoneActive = false
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
    
    /// Plays a voice sample with reliable completion handling
    private func playSample(voice: (String, String, String)) {
        print("Playing sample for \(voice.0)")
        
        // Track which sample we're playing
        currentSample = voice.0
        
        // Update state
        selectedVoice = voice.1
        activeVoice = voice.1
        isListening = false
        isSamplePlaying = true
        
        // Add haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Stop current speech recognition
        speechRecognizers.stopRecording()
        
        // Ensure microphone is shown as inactive
        withAnimation {
            isMicrophoneActive = false
        }
        
        // Reset audio session for clean playback
        resetAudioSession()
        
        // Play the voice sample
        ttsManager.speak(voice.2, voice: voice.1) {
            print("Sample finished for \(voice.0), resuming listening")
            self.samplePlaybackFinished()
        }
        
        // Failsafe 1: At estimated duration
        let estimatedDuration = voice.0 == "Dan" ? TimeInterval(7.0) : TimeInterval(6.0)
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
    
    /// Handles sample playback completion with proper state restoration
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
    
    /// Prompts the user to select a voice first
    private func promptForSelection() {
        isListening = false
        speechRecognizers.stopRecording()
        
        // Ensure microphone indicator is off
        withAnimation {
            isMicrophoneActive = false
        }
        
        // Error feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        
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
    
    /// Finalizes voice selection and navigates forward
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
        isSamplePlaying = true // Use this flag to prevent other audio
        speechRecognizers.stopRecording()
        
        // Success feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Ensure microphone indicator is off
        withAnimation {
            isMicrophoneActive = false
        }
        
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

// MARK: - Simple Component Views

/// Simple animated particle background
struct SimpleParticleBackground: View {
    
    // Use fewer particles to avoid performance issues
    let particleCount = 20
    
    var body: some View {
        ZStack {
            // Creating individual particles
            ForEach(0..<particleCount, id: \.self) { index in
                SimpleParticle(index: index)
            }
        }
    }
}

/// Individual animated particle
struct SimpleParticle: View {
    let index: Int
    
    @State private var position = CGPoint.zero
    @State private var size: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(Color(red: 27/255, green: 255/255, blue: 255/255))
            .frame(width: size, height: size)
            .opacity(opacity)
            .blur(radius: size * 0.2)
            .position(position)
            .onAppear {
                // Initialize with random properties
                let screenWidth = UIScreen.main.bounds.width
                let screenHeight = UIScreen.main.bounds.height
                
                // Set initial position
                position = CGPoint(
                    x: CGFloat.random(in: 0...screenWidth),
                    y: CGFloat.random(in: 0...screenHeight)
                )
                
                // Set size and opacity
                size = CGFloat.random(in: 3...8)
                opacity = Double.random(in: 0.1...0.4)
                
                // Start animation with delay based on index
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.1) {
                    startAnimation()
                }
            }
    }
    
    private func startAnimation() {
        isAnimating = true
        
        // Animate position, size and opacity with different durations
        let duration = Double.random(in: 10...20)
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        withAnimation(Animation.linear(duration: duration).repeatForever(autoreverses: false)) {
            // Move to a new random position
            position = CGPoint(
                x: CGFloat.random(in: 0...screenWidth),
                y: CGFloat.random(in: 0...screenHeight)
            )
        }
        
        // Pulse size and opacity
        withAnimation(Animation.easeInOut(duration: Double.random(in: 2...4)).repeatForever(autoreverses: true)) {
            size = CGFloat.random(in: 4...10)
            opacity = Double.random(in: 0.2...0.5)
        }
    }
}

/// Simple grid of voice selection orbs
struct SimpleVoiceGrid: View {
    let voices: [(String, String, String)]
    @Binding var selectedVoice: String?
    @Binding var activeVoice: String?
    let onActivate: ((String, String, String)) -> Void
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color(red: 27/255, green: 255/255, blue: 255/255).opacity(0.3), lineWidth: 2)
                .frame(width: 300, height: 300)
            
            // Voice orbs
            VStack(spacing: 60) {
                HStack(spacing: 60) {
                    SimpleVoiceOrb(
                        name: voices[0].0,
                        isSelected: selectedVoice == voices[0].1,
                        isActive: activeVoice == voices[0].1,
                        onActivate: { onActivate(voices[0]) }
                    )
                    
                    SimpleVoiceOrb(
                        name: voices[1].0,
                        isSelected: selectedVoice == voices[1].1,
                        isActive: activeVoice == voices[1].1,
                        onActivate: { onActivate(voices[1]) }
                    )
                }
                
                HStack(spacing: 60) {
                    SimpleVoiceOrb(
                        name: voices[2].0,
                        isSelected: selectedVoice == voices[2].1,
                        isActive: activeVoice == voices[2].1,
                        onActivate: { onActivate(voices[2]) }
                    )
                    
                    SimpleVoiceOrb(
                        name: voices[3].0,
                        isSelected: selectedVoice == voices[3].1,
                        isActive: activeVoice == voices[3].1,
                        onActivate: { onActivate(voices[3]) }
                    )
                }
            }
        }
        .drawingGroup() // Use Metal acceleration for the entire composition
    }
}

/// Individual voice selection orb
struct SimpleVoiceOrb: View {
    let name: String
    let isSelected: Bool
    let isActive: Bool
    let onActivate: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onActivate) {
            ZStack {
                // Glow effect
                if isActive || isSelected || isHovered {
                    Circle()
                        .fill(
                            Color(red: 27/255, green: 255/255, blue: 255/255)
                                .opacity(isActive ? 0.4 : isSelected ? 0.3 : 0.2)
                        )
                        .frame(width: 100, height: 100)
                        .blur(radius: 10)
                }
                
                // Main circle
                Circle()
                    .fill(Color(red: 46/255, green: 49/255, blue: 146/255))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(
                                Color(red: 27/255, green: 255/255, blue: 255/255),
                                lineWidth: isActive ? 3 : isSelected ? 2 : 1.5
                            )
                    )
                
                // Name text
                Text(name)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .scaleEffect(isActive ? 1.1 : isSelected ? 1.05 : isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Simple microphone indicator
struct SimpleMicIndicator: View {
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color(red: 46/255, green: 49/255, blue: 146/255).opacity(0.7))
                .frame(width: 50, height: 50)
                .overlay(
                    Circle()
                        .stroke(Color(red: 27/255, green: 255/255, blue: 255/255).opacity(0.8), lineWidth: 2)
                        .scaleEffect(isPulsing ? 1.3 : 1.0)
                        .opacity(isPulsing ? 0.5 : 1.0)
                )
            
            // Microphone icon
            Image(systemName: "mic.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

/// Voice sample text overlay
struct SamplePlaybackView: View {
    let voiceText: String
    
    @State private var isVisible = false
    
    var body: some View {
        VStack {
            Spacer()
            
            Text(voiceText)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 46/255, green: 49/255, blue: 146/255).opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(red: 27/255, green: 255/255, blue: 255/255).opacity(0.5), lineWidth: 1.5)
                        )
                )
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 20)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = true
            }
        }
    }
}
