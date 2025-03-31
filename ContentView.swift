import SwiftUI

struct ContentView: View {
    @State private var flowState: FlowState = .loading
    @State private var selectedVoice: String = "en-US-AriaNeural"
    @State private var userName: String = "User" // To store the name for HomeView
    
    enum FlowState {
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
            switch flowState {
            case .loading:
                LoadingView(
                    onComplete: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                flowState = .welcome
                            }
                        }
                    }
                )
                .transition(.opacity)
            case .welcome:
                WelcomeView(
                    onAppearAction: {
                        print("WelcomeView appeared")
                    },
                    onNext: {
                        withAnimation {
                            flowState = .onboarding
                        }
                    },
                    onDirectHome: {
                        withAnimation {
                            flowState = .home
                        }
                    },
                    onPermissionDenied: {
                        withAnimation {
                            flowState = .permissionDenied
                        }
                    }
                )
                .transition(.opacity)
            case .onboarding:
                OnBoardingView(
                    onComplete: { // Changed from onSuccess to match your file
                        withAnimation {
                            flowState = .voiceSelection
                        }
                    }
                )
                .transition(.opacity)
            case .voiceSelection:
                VoiceSelectionView(
                    onVoiceSelected: { voice in
                        selectedVoice = voice
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation {
                                flowState = .nameInput
                            }
                        }
                    }
                )
                .transition(.opacity)
            case .nameInput:
                NameInputView(
                    selectedVoice: selectedVoice,
                    onComplete: { name in
                        userName = name // Store the name
                        withAnimation {
                            flowState = .home
                        }
                    }
                )
                .transition(.opacity)
            case .home:
                HomeView() // Updated to not require userName since your HomeView doesn’t use it
                    .transition(.opacity)
            case .permissionDenied:
                PermissionDeniedView(
                    onRetry: {
                        withAnimation {
                            flowState = .loading // Retry goes back to start
                        }
                    }
                )
                .transition(.opacity)
            }
        }
    }
}
