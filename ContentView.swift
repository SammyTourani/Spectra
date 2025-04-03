// [[[cog
// import cog
// cog.outl(f'// -*- coding: utf-8 -*-')
// ]]]
// -*- coding: utf-8 -*-
// [[[end]]]
import SwiftUI

struct ContentView: View {
    @State private var flowState: FlowState = .loading
    // Store selected voice and user name here
    @State private var selectedVoice: String = "en-US-AriaNeural" // Default voice
    @State private var userName: String = "User"

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
            // Use AnyView to handle transitions between potentially different view types smoothly
            AnyView(currentView)
                 .transition(.opacity.animation(.easeInOut(duration: 0.4))) // Apply transition to AnyView
        }
        // Use task for async operations tied to view lifecycle if needed
         .task {
              // Example: Preload resources if necessary based on state
         }
    }

    // Computed property to determine the current view based on flowState
    @ViewBuilder
    private var currentView: some View {
        switch flowState {
        case .loading:
            LoadingView(
                onComplete: {
                    // Delay slightly before moving to welcome
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { // Adjusted delay
                        flowState = .welcome
                    }
                }
            )
        case .welcome:
            WelcomeView(
                onAppearAction: {
                    print("WelcomeView appeared")
                },
                onNext: {
                    flowState = .onboarding
                },
                onDirectHome: {
                    // If skipping, go directly home (using default voice/name)
                    flowState = .home
                },
                onPermissionDenied: {
                    flowState = .permissionDenied
                }
            )
        case .onboarding:
            OnBoardingView(
                onComplete: {
                    flowState = .voiceSelection
                }
            )
        case .voiceSelection:
            VoiceSelectionView(
                onVoiceSelected: { voice in
                    print("Voice Selected in ContentView: \(voice)")
                    selectedVoice = voice // <-- STORE THE SELECTED VOICE
                    // Add a small delay for visual feedback before transitioning
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                         flowState = .nameInput
                    }
                }
            )
        case .nameInput:
            NameInputView(
                selectedVoice: selectedVoice, // Pass selected voice TO NameInputView
                onComplete: { name in
                    print("Name Entered in ContentView: \(name)")
                    userName = name // <-- STORE THE USER NAME
                     // Add a small delay for visual feedback
                     DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                          flowState = .home
                     }
                }
            )
        case .home:
            // Pass the selected voice and user name TO HomeView
            HomeView(selectedVoice: selectedVoice, userName: userName)

        case .permissionDenied:
            PermissionDeniedView(
                onRetry: {
                     // Reset to welcome might be better than loading if permissions were the only issue
                     flowState = .welcome
                    // Or go back to loading if a full reset is needed:
                    // flowState = .loading
                }
            )
        }
    }
}
