import SwiftUI
import AVFoundation

struct LoadingView: View {
    let onComplete: () -> Void
    
    @StateObject private var audioManager = AudioManager()
    @State private var logoScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            AnimatedMeshGradient()
            
            RadialGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.3), Color.clear]),
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 250, height: 250)
                    .scaleEffect(logoScale)
                    .shadow(color: Color.black.opacity(0.5), radius: 30, x: 0, y: 0)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            }
            .padding(.vertical, 80)
        }
        .onAppear {
            AudioSessionManager.shared.activate()
            audioManager.playAudio(named: "start_up") {
                print("Start_up chime finished")
                AudioSessionManager.shared.deactivate()
                onComplete()
            }
            withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                logoScale = 1.2
            }
        }
    }
}

struct AnimatedMeshGradient: View {
    @State private var phase: Double = 0.0
    let cellSize: CGFloat = 50

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let cols = Int(size.width / cellSize)
                let rows = Int(size.height / cellSize)
                
                for col in 0...cols {
                    for row in 0...rows {
                        let x = CGFloat(col) * cellSize
                        let y = CGFloat(row) * cellSize
                        let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                        let hue = (sin(phase + Double(col) * 0.3) + cos(phase + Double(row) * 0.3) + 2) / 4
                        let color = Color(hue: hue, saturation: 0.6, brightness: 0.8)
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
            .onAppear {
                withAnimation(Animation.linear(duration: 3).repeatForever(autoreverses: false)) {
                    phase = 2 * .pi
                }
            }
        }
        .ignoresSafeArea()
    }
}
