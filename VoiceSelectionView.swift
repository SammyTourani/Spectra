import SwiftUI
import AVFoundation
import Speech

struct VoiceSelectionView: View {
    let onVoiceSelected: (String) -> Void
    
    @StateObject private var speechRecognizers = SpeechRecognizers()
    @StateObject private var ttsManager = AzureTTSManager(
        apiKey: "BcZtnvJFdIxg9rexNdQUwOQYFay9YaGZMPUkBKPfgtE8VBEbQIgJJQQJ99BCACBsN54XJ3w3AAAYACOGpSuV",
        region: "canadacentral"
    )
    @State private var voices = [
        ("Amy", "en-US-AriaNeural", "Hi, I’m Amy—clear and friendly. Say 'Select' to choose me."),
        ("Ben", "en-US-GuyNeural", "I’m Ben—calm and steady. Say 'Select' to pick me."),
        ("Clara", "en-US-JennyNeural", "Hey, I’m Clara—warm and bright. Say 'Select' to join me."),
        ("Dan", "en-US-ChristopherNeural", "I’m Dan—strong and direct. Say 'Select' to activate me.")
    ]
    @State private var selectedVoice: String? = nil
    @State private var activeVoice: String? = nil
    @State private var isListening = false
    @State private var wavePhase: Double = 0.0
    @State private var isTextVisible = false
    
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
            
            if isListening {
                ListeningIndicator(active: activeVoice != nil)
                    .padding(.bottom, 30)
                    .padding(.trailing, 30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .onAppear {
            isTextVisible = true
            requestMicPermission()
        }
    }
    
    private func requestMicPermission() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    AudioSessionManager.shared.activate()
                    // Fixed: Added 'voice: voices[0].1' to provide the missing parameter
                    ttsManager.speak("Say Amy, Ben, Clara, or Dan to hear me, then 'Select' to choose.", voice: voices[0].1) {
                        startListening()
                    }
                    withAnimation(Animation.linear(duration: 8).repeatForever(autoreverses: false)) {
                        wavePhase = 2 * .pi
                    }
                } else {
                    print("Microphone permission denied")
                }
            }
        }
    }
    
    private func playSample(voice: (String, String, String)) {
        selectedVoice = voice.1
        activeVoice = voice.1
        speechRecognizers.stopRecording()
        AudioSessionManager.shared.deactivate() // Ensure clean slate
        AudioSessionManager.shared.activate()
        ttsManager.speak(voice.2, voice: voice.1) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                activeVoice = nil
                isListening = false // Reset state
                startListening()
            }
        }
    }
    
    private func startListening() {
        guard !isListening else { print("Already listening"); return }
        isListening = true
        AudioSessionManager.shared.activate()
        speechRecognizers.startRecording { text in
            let lowerText = text.lowercased().trimmingCharacters(in: .whitespaces)
            print("Heard: \(lowerText)")
            if let voice = voices.first(where: { $0.0.lowercased() == lowerText }) {
                print("Matched voice: \(voice.0)")
                playSample(voice: voice)
            } else if lowerText == "select", let selected = selectedVoice {
                print("Selecting voice: \(selected)")
                speechRecognizers.stopRecording()
                isListening = false
                AudioSessionManager.shared.activate()
                ttsManager.speak("Voice selected. Let’s proceed.", voice: selected) {
                    AudioSessionManager.shared.deactivate()
                    onVoiceSelected(selected)
                }
            } else {
                print("No match for: \(lowerText)")
            }
        }
    }
}

// MARK: - Components

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
                .fill(Color(hex: "#2E3192").opacity(0.6))
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .stroke(Color(hex: "#1BFFFF").opacity(0.8), lineWidth: 2)
                        .scaleEffect(1.0 + pulsePhase * 0.3)
                        .opacity(1.0 - pulsePhase)
                )
                .shadow(color: Color(hex: "#1BFFFF").opacity(0.3), radius: 4)
            
            Image(systemName: "mic.fill")
                .font(.system(size: 16))
                .foregroundColor(.white)
                .scaleEffect(active ? 1.2 : 1.0)
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulsePhase = 1.0
            }
        }
    }
}
