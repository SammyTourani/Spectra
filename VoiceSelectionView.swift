import SwiftUI
import AVFoundation
import Speech

struct VoiceSelectionView: View {
    let onVoiceSelected: (String) -> Void
    
    @StateObject private var speechRecognizers = SpeechRecognizers()
    private let ttsManager = AzureTTSManager.shared
    
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
    @State private var hasSelectedVoice = false
    
    // Improve mic indication with a namespace for animations
    @Namespace private var micAnimation
    @State private var microphoneActive = false
    @State private var microphoneOpacity = 0.0
    
    // Dedicated timer for state management
    @State private var stateTimers: [String: DispatchWorkItem] = [:]
    
    var body: some View {
        ZStack {
            // Use drawingGroup for better GPU rendering of background
            ParticleBackground()
                .drawingGroup() // Use Metal acceleration for particles
                .ignoresSafeArea()
            
            SineWaveBackground(phase: $wavePhase)
                .drawingGroup() // Use Metal acceleration for sine waves
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
            
            // Improve mic indicator positioning and animation
            ListeningIndicator(active: microphoneActive)
                .padding(.bottom, 30)
                .padding(.trailing, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .opacity(microphoneOpacity)
                .animation(.easeInOut(duration: 0.3), value: microphoneOpacity)
                .allowsHitTesting(false)
        }
        .onAppear {
            print("VoiceSelectionView appeared")
            clearAllTimers()
            
            // Reset states on appear
            isTextVisible = true
            hasSelectedVoice = false
            selectedVoice = nil
            activeVoice = nil
            microphoneActive = false
            microphoneOpacity = 0.0
            
            // Start wave animation
            withAnimation(Animation.linear(duration: 8).repeatForever(autoreverses: false)) {
                wavePhase = 2 * .pi
            }
            
            // Initialize view with a short delay
            let initTimer = DispatchWorkItem {
                initializeView()
            }
            stateTimers["init"] = initTimer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: initTimer)
        }
        .onDisappear {
            print("VoiceSelectionView disappeared")
            clearAllTimers()
            cleanupView()
        }
    }
    
    // Clear all timers to prevent race conditions
    private func clearAllTimers() {
        for (_, timer) in stateTimers {
            timer.cancel()
        }
        stateTimers.removeAll()
    }
    
    private func initializeView() {
        guard !viewInitialized else { return }
        
        print("Initializing voice selection view")
        viewInitialized = true
        
        let startTimer = DispatchWorkItem {
            resetAudioSession()
            
            let introTimer = DispatchWorkItem {
                AudioSessionManager.shared.activate()
                ttsManager.speak("Say Amy, Ben, Clara, or Dan to hear me, then 'Select' to choose.", voice: voices[0].1) {
                    print("Introduction complete, starting listening")
                    startListening()
                }
                
                // Failsafe timer
                let failsafeTimer = DispatchWorkItem {
                    if !isListening && !isSamplePlaying {
                        print("Failsafe: Starting listening after introduction")
                        startListening()
                    }
                }
                stateTimers["failsafe"] = failsafeTimer
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: failsafeTimer)
            }
            
            stateTimers["intro"] = introTimer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: introTimer)
        }
        
        stateTimers["start"] = startTimer
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: startTimer)
    }
    
    private func cleanupView() {
        print("Cleaning up view resources")
        clearAllTimers()
        
        speechRecognizers.stopRecording()
        ttsManager.cancelAllSpeech()
        AudioSessionManager.shared.deactivate()
        isListening = false
        
        // Ensure microphone indicator state is consistent
        microphoneActive = false
        withAnimation(.easeOut(duration: 0.3)) {
            microphoneOpacity = 0.0
        }
        
        isSamplePlaying = false
    }
    
    private func resetAudioSession() {
        AudioSessionManager.shared.resetAndActivate()
    }
    
    private func startListening() {
        print("Starting voice command listening")
        
        if isSamplePlaying || hasSelectedVoice {
            print("Sample playing or voice already selected, deferring listening")
            return
        }
        
        // Ensure all timers are cancelled to prevent overlaps
        clearAllTimers()
        
        speechRecognizers.stopRecording()
        resetAudioSession()
        
        isListening = true
        micRestartAttempts = 0
        
        // The key improvement - set both states together with animation
        DispatchQueue.main.async {
            self.microphoneActive = true
            withAnimation(.easeInOut(duration: 0.3)) {
                self.microphoneOpacity = 1.0
            }
            print("Microphone active - showing indicator")
        }
        
        speechRecognizers.startRecording(
            onMicStateChange: { active in
                DispatchQueue.main.async {
                    // Always update both properties together on main thread
                    if active != self.microphoneActive {
                        self.microphoneActive = active
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.microphoneOpacity = active ? 1.0 : 0.0
                        }
                        print(active ? "Microphone active - showing indicator" : "Microphone inactive - hiding indicator")
                    }
                }
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
        
        // Create a restart check timer
        let restartTimer = DispatchWorkItem {
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
        
        stateTimers["restart"] = restartTimer
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: restartTimer)
    }
    
    private func resetAndRestartAudio() {
        print("Full audio system reset")
        
        // Clear all timers
        clearAllTimers()
        
        speechRecognizers.stopRecording()
        ttsManager.cancelAllSpeech()
        AudioSessionManager.shared.deactivate()
        
        // Update microphone indicator state on main thread
        DispatchQueue.main.async {
            self.microphoneActive = false
            withAnimation(.easeOut(duration: 0.3)) {
                self.microphoneOpacity = 0.0
            }
        }
        
        let resetTimer = DispatchWorkItem {
            self.resetAudioSession()
            self.micRestartAttempts = 0
            self.isListening = false
            self.isSamplePlaying = false
            
            let startTimer = DispatchWorkItem {
                self.startListening()
            }
            self.stateTimers["start"] = startTimer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: startTimer)
        }
        
        stateTimers["reset"] = resetTimer
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: resetTimer)
    }
    
    private func playSample(voice: (String, String, String)) {
        print("Playing sample for \(voice.0)")
        
        // Clear all timers to prevent overlaps
        clearAllTimers()
        
        currentSample = voice.0
        selectedVoice = voice.1
        activeVoice = voice.1
        isListening = false
        
        // Update microphone indicator state on main thread
        DispatchQueue.main.async {
            self.microphoneActive = false
            withAnimation(.easeOut(duration: 0.3)) {
                self.microphoneOpacity = 0.0
            }
        }
        
        isSamplePlaying = true
        speechRecognizers.stopRecording()
        resetAudioSession()
        
        AudioSessionManager.shared.activate()
        ttsManager.speak(voice.2, voice: voice.1) {
            print("Sample finished for \(voice.0), resuming listening")
            self.samplePlaybackFinished()
        }
        
        // Calculate a reasonable timeout for the sample
        let estimatedDuration = voice.0 == "Dan" ? TimeInterval(7.0) : TimeInterval(6.0)
        
        // Set failsafe timers for sample completion
        let failsafe1 = DispatchWorkItem {
            if self.isSamplePlaying && self.currentSample == voice.0 {
                print("Failsafe 1: Sample may have completed without callback")
                self.samplePlaybackFinished()
            }
        }
        
        let failsafe2 = DispatchWorkItem {
            if self.isSamplePlaying && self.currentSample == voice.0 {
                print("Failsafe 2: Forcing sample completion")
                self.samplePlaybackFinished()
            }
        }
        
        stateTimers["failsafe1"] = failsafe1
        stateTimers["failsafe2"] = failsafe2
        
        DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration, execute: failsafe1)
        DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration + 2.0, execute: failsafe2)
    }
    
    private func samplePlaybackFinished() {
        guard isSamplePlaying else { return }
        
        print("Sample playback finished, resetting state")
        isSamplePlaying = false
        currentSample = nil
        
        // Create timer for resuming listening
        let resumeTimer = DispatchWorkItem {
            self.startListening()
        }
        
        stateTimers["resume"] = resumeTimer
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: resumeTimer)
    }
    
    private func promptForSelection() {
        // Clear timers
        clearAllTimers()
        
        isListening = false
        
        // Update microphone indicator state on main thread
        DispatchQueue.main.async {
            self.microphoneActive = false
            withAnimation(.easeOut(duration: 0.3)) {
                self.microphoneOpacity = 0.0
            }
        }
        
        speechRecognizers.stopRecording()
        resetAudioSession()
        
        AudioSessionManager.shared.activate()
        ttsManager.speak("Please say a name first to preview a voice.", voice: voices[0].1) {
            self.startListening()
        }
        
        // Set failsafe timer
        let promptTimer = DispatchWorkItem {
            if !self.isListening && !self.isSamplePlaying && !self.hasSelectedVoice {
                self.startListening()
            }
        }
        
        stateTimers["prompt"] = promptTimer
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: promptTimer)
    }
    
    private func selectVoice(_ voice: String) {
        if hasSelectedVoice {
            print("Voice already selected, ignoring duplicate selection")
            return
        }
        
        print("Voice selected: \(voice)")
        
        // Clear timers
        clearAllTimers()
        
        hasSelectedVoice = true
        isListening = false
        
        // Update microphone indicator state on main thread
        DispatchQueue.main.async {
            self.microphoneActive = false
            withAnimation(.easeOut(duration: 0.3)) {
                self.microphoneOpacity = 0.0
            }
        }
        
        isSamplePlaying = true
        speechRecognizers.stopRecording()
        resetAudioSession()
        
        AudioSessionManager.shared.activate()
        ttsManager.speak("Voice selected. Let's proceed.", voice: voice) {
            self.cleanupView()
            print("Voice selection complete - navigating to next screen with voice: \(voice)")
            DispatchQueue.main.async {
                self.onVoiceSelected(voice)
            }
        }
        
        // Set navigation failsafe timer
        let navTimer = DispatchWorkItem {
            if self.hasSelectedVoice && self.isSamplePlaying {
                print("Navigation failsafe triggered")
                self.cleanupView()
                print("Voice selection complete (failsafe) - navigating to next screen with voice: \(voice)")
                DispatchQueue.main.async {
                    self.onVoiceSelected(voice)
                }
            }
        }
        
        stateTimers["navigation"] = navTimer
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: navTimer)
    }
}

// The rest of the component definitions remain the same
struct ParticleBackground: View {
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                ZStack {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 46/255, green: 49/255, blue: 146/255),
                            Color(red: 27/255, green: 255/255, blue: 255/255)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    ForEach(0..<10) { i in
                        Circle()
                            .fill(Color(red: 27/255, green: 255/255, blue: 255/255).opacity(0.4))
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
                
                for y in stride(from: 0, through: height, by: 40) {
                    let path = Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        for x in stride(from: 0, through: width, by: 5) {
                            let sineValue = sin(frequency * x + phase + y * 0.02)
                            let offsetY = y + sineValue * waveHeight
                            p.addLine(to: CGPoint(x: x, y: offsetY))
                        }
                    }
                    context.stroke(path, with: .color(Color(red: 27/255, green: 255/255, blue: 255/255).opacity(0.1)), lineWidth: 1)
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
                .stroke(Color(red: 27/255, green: 255/255, blue: 255/255).opacity(0.3), lineWidth: 2)
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
                    gradient: Gradient(colors: [
                        Color(red: 27/255, green: 255/255, blue: 255/255).opacity(isActive ? 0.5 : isSelected ? 0.3 : 0),
                        .clear
                    ]),
                    center: .center,
                    startRadius: 20,
                    endRadius: 60
                ))
                .frame(width: 120, height: 120)
            
            Circle()
                .fill(Color(red: 46/255, green: 49/255, blue: 146/255).opacity(0.8))
                .frame(width: 80, height: 80)
                .overlay(Circle().stroke(Color(red: 27/255, green: 255/255, blue: 255/255), lineWidth: 2))
                .overlay(
                    Text(voice.0)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                )
                .scaleEffect(isActive ? 1.1 : isSelected ? 1.05 : 1.0)
                .opacity(isActive || isSelected ? 1.0 : 0.8)
                .animation(.easeInOut(duration: 0.3), value: isActive || isSelected)
                .shadow(color: Color(red: 27/255, green: 255/255, blue: 255/255).opacity(isActive ? 0.5 : 0), radius: 6)
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
                .fill(Color(red: 46/255, green: 49/255, blue: 146/255).opacity(active ? 0.6 : 0.3))
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .stroke(Color(red: 27/255, green: 255/255, blue: 255/255).opacity(active ? 0.8 : 0.4), lineWidth: 2)
                        .scaleEffect(active ? 1.0 + pulsePhase * 0.3 : 1.0)
                        .opacity(active ? 1.0 - pulsePhase : 1.0)
                )
                .shadow(color: Color(red: 27/255, green: 255/255, blue: 255/255).opacity(active ? 0.3 : 0), radius: 4)
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
                withAnimation(.easeOut(duration: 0.3)) {
                    pulsePhase = 0.0
                }
            }
        }
    }
}
