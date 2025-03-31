import SwiftUI
import AVFoundation
import Speech

struct WelcomeView: View {
    let onAppearAction: () -> Void
    let onNext: () -> Void
    let onDirectHome: () -> Void
    let onPermissionDenied: () -> Void
    
    @StateObject private var audioManager = AudioManager()
    @State private var currentStep: WelcomeStep = .initialWelcome
    @State private var animateLogo = false
    @State private var textOpacity: Double = 0.0
    @State private var isSkipping = false
    
    enum WelcomeStep {
        case initialWelcome
        case waitingForPermissions
        case permissionsGranted
    }
    
    var body: some View {
        ZStack {
            FullScreenWaveBackground()
                .ignoresSafeArea()
            
            AnimatedOverlay()
            
            VStack(spacing: 20) {
                Spacer()
                
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 230, height: 230)
                    .scaleEffect(animateLogo ? 1.0 : 0.96)
                    .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: animateLogo)
                
                if isSkipping {
                    Text("Skipping to Home...")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                        .transition(.opacity)
                } else {
                    if currentStep == .initialWelcome {
                        Text("Welcome to Spectra")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .opacity(textOpacity)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if currentStep == .waitingForPermissions {
                        Text("Tap to begin")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .opacity(textOpacity)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if currentStep == .permissionsGranted {
                        VStack(spacing: 10) {
                            Text("All set! Loading...")
                                .font(.system(size: 28, weight: .semibold))
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                        }
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .opacity(textOpacity)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 30)
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.8)
                .onEnded { _ in
                    handleLongPress()
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    if currentStep == .waitingForPermissions && !isSkipping {
                        requestPermissions()
                    }
                }
        )
        .onAppear {
            onAppearAction()
            animateLogo = true
            withAnimation(.easeIn(duration: 1.5)) {
                textOpacity = 1.0
            }
            AudioSessionManager.shared.activate()
            audioManager.playAudio(named: "welcome_audio") {
                withAnimation(.easeInOut(duration: 0.5)) {
                    textOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        currentStep = .waitingForPermissions
                        textOpacity = 1.0
                    }
                    AudioSessionManager.shared.deactivate()
                }
            }
        }
        .onDisappear {
            audioManager.stopAudio()
            AudioSessionManager.shared.deactivate()
        }
    }
    
    private func handleLongPress() {
        // Stop any playing audio immediately
        audioManager.stopAudio()
        AudioSessionManager.shared.deactivate()
        
        withAnimation(.easeIn(duration: 0.3)) {
            isSkipping = true
            textOpacity = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onDirectHome()
        }
    }
    
    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { cameraGranted in
            AVAudioApplication.requestRecordPermission { micGranted in
                SFSpeechRecognizer.requestAuthorization { speechStatus in
                    let speechGranted = speechStatus == .authorized
                    DispatchQueue.main.async {
                        if cameraGranted && micGranted && speechGranted {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                currentStep = .permissionsGranted
                                textOpacity = 1.0
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation(.easeOut(duration: 0.5)) {
                                    textOpacity = 0.0
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    onNext()
                                }
                            }
                        } else {
                            onPermissionDenied()
                        }
                    }
                }
            }
        }
    }
}

// Keep existing AnimatedOverlay and FullScreenWaveBackground structs as they are

struct AnimatedOverlay: View {
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        Circle()
            .stroke(Color.white.opacity(0.3), lineWidth: 2)
            .frame(width: 350, height: 350)
            .scaleEffect(scale)
            .animation(Animation.easeInOut(duration: 3).repeatForever(autoreverses: true), value: scale)
            .onAppear {
                scale = 1.3
            }
    }
}

struct FullScreenWaveBackground: View {
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
