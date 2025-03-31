import SwiftUI

struct ContentView: View {
    @State private var flowState: AppFlowState = .loading
    @State private var selectedVoice: String = "en-US-JennyNeural"
    @State private var userName: String = ""
    
    enum AppFlowState {
        case loading
        case welcome
        case onboarding
        case voiceSelection
        case nameInput
        case home
        case permissionDenied
    }
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(hex: "#2E3192"), Color(hex: "#1BFFFF")]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            switch flowState {
            case .loading:
                LoadingView(onComplete: {
                    flowState = .welcome
                })
                .transition(.opacity)
                
            case .welcome:
                WelcomeView(
                    onAppearAction: {},
                    onNext: { flowState = .onboarding },
                    onDirectHome: { flowState = .home }, // Add new closure for direct home navigation
                    onPermissionDenied: { flowState = .permissionDenied }
                )
                .transition(.opacity)
                
            case .onboarding:
                OnBoardingView(
                    onComplete: { flowState = .voiceSelection }
                )
                .transition(.opacity)
                
            case .voiceSelection:
                VoiceSelectionView(
                    onVoiceSelected: { voice in
                        selectedVoice = voice
                        flowState = .nameInput
                    }
                )
                .transition(.opacity)
                
            case .nameInput:
                NameInputView(
                    selectedVoice: selectedVoice,
                    onComplete: { name in
                        userName = name
                        flowState = .home
                    }
                )
                .transition(.opacity)
                
            case .home:
                HomeView()
                    .transition(.opacity)
                
            case .permissionDenied:
                PermissionDeniedView(
                    onRetry: { flowState = .welcome }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: flowState)
    }
}

// Keep the Color extension as it is
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
