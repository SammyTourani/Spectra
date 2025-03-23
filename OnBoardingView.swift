import SwiftUI
import AVFoundation
import Speech

struct OnBoardingView: View {
    let onNext: () -> Void
    
    @StateObject private var audioManager = AudioManager()
    @StateObject private var speechRecognizers = SpeechRecognizers()
    @StateObject private var ttsManager = AzureTTSManager(
        apiKey: "BcZtnvJFdIxg9rexNdQUwOQYFay9YaGZMPUkBKPfgtE8VBEbQIgJJQQJ99BCACBsN54XJ3w3AAAYACOGpSuV",
        region: "canadacentral"
    )
    @State private var currentStep: OnboardingStep = .initial
    @State private var pulseAnimation = false
    @State private var waveScale: CGFloat = 1.0
    @State private var waveOpacity: Double = 0.5
    @State private var showSuccessAnimation = false
    @State private var instructionText: String = "Spectra is explaining how to use the app"
    
    enum OnboardingStep {
        case initial
        case playing
        case listening
        case success
    }
    
    var body: some View {
        ZStack {
            DynamicWaveBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Text("Let's Get Started")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
                
                ZStack {
                    if currentStep == .initial || currentStep == .playing || currentStep == .listening {
                        VStack(spacing: 20) {
                            if currentStep != .listening {
                                ZStack {
                                    ForEach(0..<3) { i in
                                        Circle()
                                            .stroke(Color.white.opacity(waveOpacity / Double(i + 1)), lineWidth: 3)
                                            .frame(width: 120 + CGFloat(i * 30), height: 120 + CGFloat(i * 30))
                                            .scaleEffect(currentStep == .playing ? waveScale : 1.0)
                                    }
                                    Image(systemName: "waveform.circle.fill")
                                        .resizable()
                                        .foregroundColor(.white)
                                        .frame(width: 80, height: 80)
                                        .shadow(color: .black.opacity(0.2), radius: 5)
                                }
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 160, height: 160)
                                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                                    Circle()
                                        .fill(Color.white.opacity(0.4))
                                        .frame(width: 120, height: 120)
                                        .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                                    Circle()
                                        .fill(Color.blue.opacity(0.7))
                                        .frame(width: 100, height: 100)
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.white)
                                }
                            }
                            
                            Text(instructionText)
                                .font(.system(size: currentStep == .listening ? 22 : 18, weight: currentStep == .listening ? .semibold : .regular))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                                    removal: .scale(scale: 1.1).combined(with: .opacity)
                                ))
                        }
                    }
                    
                    if currentStep == .success {
                        VStack(spacing: 20) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.3))
                                    .frame(width: 160, height: 160)
                                    .scaleEffect(showSuccessAnimation ? 1.2 : 0.8)
                                Circle()
                                    .fill(Color.green.opacity(0.7))
                                    .frame(width: 120, height: 120)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.white)
                                    .offset(y: showSuccessAnimation ? 0 : 50)
                                    .opacity(showSuccessAnimation ? 1 : 0)
                            }
                            Text("Great! Mic test successful.")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                                .opacity(showSuccessAnimation ? 1 : 0)
                                .offset(y: showSuccessAnimation ? 0 : 20)
                        }
                    }
                }
                
                HStack(spacing: 12) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(i < getStepIndex() ? Color.white : Color.white.opacity(0.4))
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            startOnboarding()
        }
    }
    
    private func startOnboarding() {
        currentStep = .playing
        
        withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            waveScale = 1.2
            waveOpacity = 0.8
        }
        
        AudioSessionManager.shared.activate()
        audioManager.playAudio(named: "onboarding_audio") {
            AudioSessionManager.shared.deactivate()
            
            withAnimation(.easeInOut(duration: 0.4)) {
                currentStep = .listening
                instructionText = "Say 'Begin' to continue..."
            }
            
            withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
            
            // Workaround: Use AVAudioSession as fallback if AVAudioApplication fails
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
            
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .default, options: [])
                try session.setActive(true)
                print("Audio session configured for recording")
            } catch {
                print("Failed to configure audio session for recording: \(error)")
                currentStep = .initial
                instructionText = "Audio setup failed. Tap to retry."
                return
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                speechRecognizers.startRecording { recognizedText in
                    print("Recognized text: \(recognizedText)")
                    if recognizedText.lowercased().contains("begin") {
                        print("Begin detected, stopping recording")
                        speechRecognizers.stopRecording()
                        AudioSessionManager.shared.deactivate()
                        
                        withAnimation {
                            currentStep = .success
                            print("Transitioned to success step")
                        }
                        
                        AudioSessionManager.shared.activate()
                        audioManager.playAudio(named: "success_chime") {
                            print("Success chime finished")
                            AudioSessionManager.shared.deactivate()
                            print("Calling onNext after chime")
                            onNext()
                        }
                        
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                            showSuccessAnimation = true
                        }
                    } else {
                        print("Did not recognize 'begin', got: \(recognizedText)")
                    }
                }
                print("Started speech recognition")
            }
        }
    }
    
    private func getStepIndex() -> Int {
        switch currentStep {
        case .initial: return 0
        case .playing: return 1
        case .listening: return 2
        case .success: return 3
        }
    }
}

struct DynamicWaveBackground: View {
    @State private var phase: Double = 0.0
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 46/255, green: 49/255, blue: 146/255),  // #2E3192
                            Color(red: 27/255, green: 255/255, blue: 255/255)  // #1BFFFF
                        ]),
                        startPoint: CGPoint(x: size.width / 2, y: 0),
                        endPoint: CGPoint(x: size.width / 2, y: size.height)
                    )
                )
                
                for wave in 0..<4 {
                    let waveOffset = Double(wave) * 0.8
                    let path = Path { path in
                        path.move(to: CGPoint(x: 0, y: size.height * (0.4 + CGFloat(wave) * 0.1)))
                        for x in stride(from: 0, through: size.width, by: 1) {
                            let y = size.height * (0.4 + CGFloat(wave) * 0.1) +
                                    sin(phase + Double(x) / 80 + waveOffset) * 40 +
                                    cos(phase * 0.3 + Double(x) / 120 + waveOffset) * 20
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        path.addLine(to: CGPoint(x: size.width, y: size.height))
                        path.addLine(to: CGPoint(x: 0, y: size.height))
                        path.closeSubpath()
                    }
                    context.fill(
                        path,
                        with: .color(Color.white.opacity(0.25 - Double(wave) * 0.05))
                    )
                }
            }
            .onAppear {
                withAnimation(Animation.linear(duration: 3).repeatForever(autoreverses: false)) {
                    phase = 2 * .pi
                }
            }
        }
    }
}
