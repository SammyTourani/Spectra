// [[[cog
// import cog
// cog.outl(f'// -*- coding: utf-8 -*-')
// ]]]
// -*- coding: utf-8 -*-
// [[[end]]]
import SwiftUI
import AVFoundation

struct HomeView: View {
    // MARK: - Input Properties
    let selectedVoice: String // Passed from ContentView
    let userName: String      // Passed from ContentView

    // MARK: - Properties
    @StateObject private var speechRecognizers = SpeechRecognizers()
    @StateObject private var ttsManager = AzureTTSManager.shared
    private let cameraManager = CameraManager()
    private let apiService = APIService.shared

    // MARK: - State Properties
    @State private var isListening = false
    @State private var isSpeaking = false
    @State private var currentRecognizedText = ""
    @State private var serverResponseText = ""
    @State private var buttonStatusText = "Tap to Speak"
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil
    @State private var lastCapturedImage: UIImage? = nil

    // MARK: - Animation Properties
    @State private var pulseAnimation = false // Controls the overall pulse effect
    @State private var gradientRotation = 0.0 // For the listening ring
    @State private var responseOpacity = 0.0
    @State private var titleScale = 1.0
    @State private var buttonTapScale = 1.0 // Specific scale for tap gesture feedback
    @State private var buttonTapRotation = 0.0 // Specific rotation for tap gesture feedback
    @State private var appearingElements = false

    // MARK: - Computed Properties (Button Gradient)
    private var currentGradientColors: [Color] {
        if isProcessing {
            return [Color.orange.opacity(0.7), Color.red.opacity(0.9)]
        } else if isListening {
            return [Color.green.opacity(0.7), Color.blue.opacity(0.9)]
        } else if isSpeaking {
            return [Color.purple.opacity(0.7), Color.pink.opacity(0.9)]
        } else { // Default idle state
            return [Color.blue.opacity(0.7), Color.purple.opacity(0.9)]
        }
    }

    private var buttonGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: currentGradientColors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundView
                contentVStack(geometry: geometry)
                // processingOverlay // Overlay might not be needed if button state changes are clear
            }
        }
        .onAppear {
            setupInitialAnimations()
            prepareAudioSession()
            greetUser()
            // Initial pulse state check
            updatePulseState()
        }
        .onDisappear {
            speechRecognizers.stopRecording()
            cameraManager.stop()
            ttsManager.cancelAllSpeech()
        }
        // Handle app going to background
         .onChange(of: UIApplication.shared.applicationState) { oldState, newState in
              if newState == .background || newState == .inactive {
                   ttsManager.cancelAllSpeech() // Cancel speech if interrupted
                   isSpeaking = false
                   isListening = false
                   isProcessing = false
                   updatePulseState() // Update pulse when becoming inactive
                   updateButtonStatusText()
              } else if newState == .active && oldState != .active {
                   // Potentially resume or reset state if needed when returning
              }
         }
         // Update pulse animation whenever relevant state changes
         .onChange(of: isListening) { _, _ in updatePulseState() }
         .onChange(of: isProcessing) { _, _ in updatePulseState() }
         .onChange(of: isSpeaking) { _, _ in updatePulseState() }
    }

    // MARK: - Main Content Layout
    private func contentVStack(geometry: GeometryProxy) -> some View {
         VStack(spacing: 25) {
              titleSection
                  .padding(.top, geometry.size.height * 0.05)
              Spacer()
              buttonSection // Contains the mainActionButton call
              statusSection
                  .padding(.top, 15)
              Spacer()
              responseSection
                  .padding(.horizontal, 30)
                  .padding(.bottom, geometry.size.height * 0.08)
                  .opacity(responseOpacity)
         }
         // Animate the appearance of the response section
         .animation(.easeIn(duration: 0.8).delay(0.2), value: responseOpacity)
    }

    // MARK: - Extracted View Sections
    private var titleSection: some View {
         VStack {
              Text("Spectra")
                  .font(.system(size: 48, weight: .bold, design: .rounded))
                  .foregroundColor(.white)
                  .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 3)
                  .overlay(
                      Text("Spectra")
                          .font(.system(size: 48, weight: .bold, design: .rounded))
                          .foregroundColor(Color.white.opacity(0.3))
                          .offset(x: 1, y: 1)
                          .blur(radius: 1)
                  )
                  .scaleEffect(titleScale)

               Text("Hi, \(userName)!")
                    .font(.title2.weight(.medium))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.top, 2)
                    .scaleEffect(titleScale)
         }
         .animation(.spring(response: 1, dampingFraction: 0.7), value: appearingElements)
    }

    private var buttonSection: some View {
         mainActionButton()
    }

    private var statusSection: some View {
         Text(buttonStatusText)
             .font(.title3.weight(.medium))
             .foregroundColor(.white)
             .padding(.horizontal, 20)
             .padding(.vertical, 10)
             .background(
                 Capsule()
                     .fill(Color.black.opacity(0.15))
                     .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
             )
             .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 3)
             .transition(.scale(scale: 0.9).combined(with: .opacity)) // Add transition
             .id(buttonStatusText) // Ensures transition triggers on text change
             .animation(.spring(response: 0.5, dampingFraction: 0.7), value: buttonStatusText)
    }

    private var responseSection: some View {
         responsePanel
    }


    // MARK: - View Components (Background, Placeholders, Response Panel etc.)
     private var backgroundView: some View {
         ZStack {
             LinearGradient(
                 gradient: Gradient(colors: [
                     Color(red: 175/255, green: 196/255, blue: 214/255),
                     Color(red: 120/255, green: 150/255, blue: 190/255)
                 ]),
                 startPoint: .top,
                 endPoint: .bottom
             )
             .ignoresSafeArea()

             // Subtle background elements (unchanged)
             Circle()
                 .fill( RadialGradient( gradient: Gradient(colors: [Color.white.opacity(0.3), Color.clear]), center: .center, startRadius: 1, endRadius: 200 ))
                 .scaleEffect(1.5)
                 .offset(x: -150, y: -300)
                 .blur(radius: 15)
             Circle()
                 .fill( RadialGradient( gradient: Gradient(colors: [Color.purple.opacity(0.2), Color.clear]), center: .center, startRadius: 1, endRadius: 250 ))
                 .scaleEffect(2.0)
                 .offset(x: 170, y: 300)
                 .blur(radius: 20)
         }
     }

     private var responsePanel: some View {
        VStack(spacing: 15) {
            VStack {
                // Determine which placeholder or content to show
                if !serverResponseText.isEmpty {
                     filledResponseView
                } else if isProcessing {
                     processingPlaceholderView
                } else if isSpeaking {
                     speakingPlaceholderView
                } else { // Idle state (after greeting or error)
                     emptyResponseView
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120) // Ensure consistent height
            .padding(.vertical, 20)
            .padding(.horizontal, 15)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.7), Color(red: 30/255, green: 40/255, blue: 60/255).opacity(0.8)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.5), Color.purple.opacity(0.3)]), startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
                    .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
            )
            // Animate changes between placeholder/content views
            .animation(.easeInOut(duration: 0.4), value: serverResponseText.isEmpty)
            .animation(.easeInOut(duration: 0.4), value: isProcessing)
            .animation(.easeInOut(duration: 0.4), value: isSpeaking)

            // Show error view if an error exists
            if let error = errorMessage {
                errorView(message: error)
                 .padding(.top, 5) // Add slight spacing
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity)) // Animate entire panel appearance
     }

    // Placeholder Views (processing, speaking, empty) - unchanged logic, added transitions
    private var processingPlaceholderView: some View {
        HStack(spacing: 12) { ProgressView().tint(.white.opacity(0.7)); Text("Processing...") }
        .font(.title3.weight(.medium)).foregroundColor(Color.white.opacity(0.7))
        .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 100)
        .transition(.opacity.animation(.easeInOut(duration: 0.3))) // Fade in/out
    }
     private var speakingPlaceholderView: some View {
        HStack(spacing: 12) { Image(systemName: "waveform").foregroundColor(Color.purple.opacity(0.8)); Text("Speaking...") }
        .font(.title3.weight(.medium)).foregroundColor(Color.white.opacity(0.7))
        .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 100)
        .transition(.opacity.animation(.easeInOut(duration: 0.3))) // Fade in/out
    }
     private var emptyResponseView: some View {
         HStack(spacing: 12) { Image(systemName: "bubble.left.and.bubble.right").foregroundColor(Color.blue.opacity(0.8)); Text("Response will appear here") }
         .font(.title3.weight(.medium)).foregroundColor(Color.white.opacity(0.7))
         .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
         .padding(.vertical, 10).padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 100)
         .transition(.opacity.animation(.easeInOut(duration: 0.3))) // Fade in/out
     }

     // Filled Response View (unchanged logic, added transitions)
     private var filledResponseView: some View {
         VStack(alignment: .leading, spacing: 10) {
             HStack {
                 Image(systemName: "speaker.wave.2.fill").foregroundColor(.green).font(.system(size: 20, weight: .semibold))
                 Text("Response Received").font(.headline).foregroundColor(.white.opacity(0.9))
                 Spacer()
                 Text(formattedTimestamp).font(.caption2).foregroundColor(.gray)
             } .padding(.bottom, 5)
             Divider().background(Color.white.opacity(0.3))
             ScrollView {
                 Text(serverResponseText)
                     .font(.body.weight(.medium)).foregroundColor(.white)
                     .padding(.vertical, 5).padding(.horizontal, 5)
                     .frame(maxWidth: .infinity, alignment: .leading)
                     .fixedSize(horizontal: false, vertical: true)
                     .id(serverResponseText) // Trigger animation on text change
             } .frame(maxHeight: 200)
         }
         .padding(.horizontal, 10)
         .transition(.opacity.combined(with: .scale(scale: 0.95)).animation(.easeInOut(duration: 0.4))) // Animate appearance
     }


    // MARK: - Main Action Button
    private func mainActionButton() -> some View {
        ZStack {
            // Background pulsing gradient circle
            Circle()
                .fill(buttonGradient)
                .frame(width: 110, height: 110)
                // Apply the main pulse animation based on the pulseAnimation state
                .scaleEffect(pulseAnimation ? 1.1 : 0.95)
                .shadow(color: buttonShadowColor, radius: pulseAnimation ? 20 : 10, x: 0, y: 0)
                // Use explicit animation tied to pulseAnimation state
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)

            // Listening progress ring (conditionally shown)
            listeningProgressRing
                 // Animate opacity change based on state
                .opacity(isListening && !isProcessing && !isSpeaking ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: isListening)
                .animation(.easeInOut(duration: 0.3), value: isProcessing)
                .animation(.easeInOut(duration: 0.3), value: isSpeaking)


            // Central Icon
            buttonIconView
                // Apply tap feedback animations
                .scaleEffect(buttonTapScale)
                .rotationEffect(.degrees(buttonTapRotation))
                // Animate the icon change between states
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isListening)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isProcessing)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isSpeaking)


        }
        .frame(width: 110, height: 110) // Keep consistent frame
        .overlay(speakingOverlay) // Add speaking overlay
        .onTapGesture { handleTapGesture() }
    }

    // Listening ring component
    private var listeningProgressRing: some View {
         let baseRing = Circle().stroke(Color.white.opacity(0.7), lineWidth: 4)
         let progressRing = Circle()
               .trim(from: 0, to: 0.75) // Keep trim static
               .stroke(Color.white, lineWidth: 4)
               .rotationEffect(.degrees(gradientRotation)) // Rotate based on state
               // Animate rotation only when listening
               .animation(isListening ? .linear(duration: 2).repeatForever(autoreverses: false) : .default, value: gradientRotation)

         return ZStack {
              baseRing
              progressRing
         }
         .frame(width: 100, height: 100) // Consistent size inside the main button
    }

    // Central button icon based on state
    @ViewBuilder private var buttonIconView: some View {
        // Use a Group to apply transitions consistently
        Group {
            if isProcessing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5) // Make progress spinner larger
            } else if isSpeaking {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 36, weight: .bold))
            } else if isListening {
                Image(systemName: "waveform") // Use waveform when listening
                    .font(.system(size: 36, weight: .bold))
            } else { // Idle state
                Image(systemName: "mic.fill")
                    .font(.system(size: 36, weight: .bold))
            }
        }
        .foregroundColor(.white)
        // Apply a fade/scale transition between icons
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
        .id(isProcessing ? "processing" : isSpeaking ? "speaking" : isListening ? "listening" : "idle") // Add ID for transitions
    }

     // Shadow color based on state
      private var buttonShadowColor: Color {
           if isProcessing { return .red.opacity(0.5) }
           if isListening { return .green.opacity(0.5) }
           if isSpeaking { return .pink.opacity(0.5) }
           return .blue.opacity(0.5) // Idle
      }

     // Overlay shown when speaking
      private var speakingOverlay: some View {
           Circle()
               .stroke(Color.purple.opacity(0.4), lineWidth: 2)
               .blur(radius: 3)
               .scaleEffect(1.15)
               .opacity(isSpeaking ? 0.7 : 0)
               // Animate the overlay appearance tied to isSpeaking state
               .animation(.easeInOut(duration: 0.4), value: isSpeaking)
      }

     // Helper to update the main pulse animation state
      private func updatePulseState() {
           let shouldPulse = isListening || isProcessing || isSpeaking
           if pulseAnimation != shouldPulse {
                pulseAnimation = shouldPulse
           }
      }

     // Helper to update the listening ring rotation
      private func updateListeningRingRotation() {
           if isListening {
               // Start rotation animation if not already rotating correctly
               // Using withAnimation ensures it restarts if needed
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    gradientRotation = 360 // Trigger animation by changing value
                }
           } else {
                // Stop rotation - setting to 0 without repeating animation
                // Use withAnimation for smooth stop
                withAnimation(.easeOut(duration: 0.3)) {
                    // Set final rotation to 0, but allow current animation cycle to finish smoothly if needed
                    // Or simply snap to 0 if preferred:
                     gradientRotation = 0
                }
           }
      }

     // Helper to update button status text based on state
      private func updateButtonStatusText() {
          if isProcessing { buttonStatusText = "Processing..." }
          else if isSpeaking { buttonStatusText = "Speaking..." }
          else if isListening { buttonStatusText = "Listening..." }
          else { buttonStatusText = "Tap to Speak" } // Idle or after error/completion
      }


    // MARK: - Error View
    private func errorView(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow).font(.system(size: 16))
            Text(message)
                .font(.subheadline).foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background( RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.2)).overlay( RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3), lineWidth: 1) ))
        .transition(.move(edge: .bottom).combined(with: .opacity)) // Animate appearance
        .onTapGesture { withAnimation { errorMessage = nil } } // Dismiss on tap
        .animation(.spring(), value: errorMessage) // Animate dismissal
    }

    // MARK: - Computed Properties for UI
    private var formattedTimestamp: String {
        let formatter = DateFormatter(); formatter.dateFormat = "h:mm:ss a"; return formatter.string(from: Date())
    }

    // MARK: - Animation Setup
    private func setupInitialAnimations() {
        // Reset state just in case
        isListening = false
        isProcessing = false
        isSpeaking = false
        titleScale = 0.8 // Start slightly smaller for spring effect
        responseOpacity = 0 // Start hidden
        appearingElements = false // Controls sequenced appearance

        // Start appearance animations
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                appearingElements = true // Trigger title animation
                titleScale = 1.0
            }
            withAnimation(.easeIn(duration: 0.8).delay(0.2)) {
                responseOpacity = 1.0 // Trigger response panel animation
            }
        }
        // Set initial button state text
        updateButtonStatusText()
    }

    // MARK: - Core Functionality
    private func prepareAudioSession() {
        AudioSessionManager.shared.activate() // Ensure session is ready
    }

    private func greetUser() {
         let greeting = "How can I help you today?"
          print("Greeting user with voice: \(selectedVoice)")
          // Ensure TTS manager uses the selected voice
          ttsManager.speak(greeting, voice: selectedVoice) {
                print("Greeting finished.")
                // Potentially update state after greeting if needed
          }
    }

    private func handleTapGesture() {
         // Prevent action if processing or already speaking (allow cancelling speech)
         guard !isProcessing else {
             print("Ignoring tap: Processing in progress.")
             generateImpactHaptic(.light) // Feedback that tap was registered but ignored
             return
         }

         if isSpeaking {
             print("Tap registered: Cancelling current speech...")
             ttsManager.cancelAllSpeech()
             generateImpactHaptic(.heavy) // Feedback for cancellation
             withAnimation(.easeInOut(duration: 0.3)) {
                 isSpeaking = false
                 // Should not be listening or processing here, so pulse stops
                 updatePulseState()
                 updateButtonStatusText() // Reset to "Tap to Speak"
             }
             return // Don't toggle listening state after cancelling speech
         }

         // Toggle listening state
         generateImpactHaptic(isListening ? .light : .medium) // Different feedback for start/stop
         isListening.toggle()
         updateButtonStatusText() // Update text immediately

         // Apply tap animation feedback
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            buttonTapScale = 0.9
            buttonTapRotation = isListening ? 5 : -5 // Subtle rotation based on action
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { // Slightly longer for effect
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                buttonTapScale = 1.0
                buttonTapRotation = 0
            }
        }

        // Start or stop listening process
        if isListening {
            startListening()
            updateListeningRingRotation() // Start ring animation
        } else {
             let textToSend = currentRecognizedText
             print("Stopping listening. Text to send: '\(textToSend)'")
             updateListeningRingRotation() // Stop ring animation
            stopListeningAndProcess(recognizedText: textToSend)
        }
    }

    // Haptic feedback helpers (unchanged)
    private func generateImpactHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) { let g = UIImpactFeedbackGenerator(style: style); g.prepare(); g.impactOccurred() }
    private func generateNotificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) { let g = UINotificationFeedbackGenerator(); g.prepare(); g.notificationOccurred(type) }

    private func startListening() {
        // Reset previous results/errors
        withAnimation {
            serverResponseText = ""
            errorMessage = nil
            currentRecognizedText = "" // Clear previous recognized text
        }
        lastCapturedImage = nil // Clear previous image
        AudioSessionManager.shared.activate() // Ensure session is active

        // Start recording
        speechRecognizers.startRecording { [self] recognizedText in
             DispatchQueue.main.async {
                  // Only update if still listening
                  if self.isListening {
                      self.currentRecognizedText = recognizedText
                      print("Recognized (intermediate): \(recognizedText)")
                  }
             }
        }
    }

    // --- MODIFIED stopListeningAndProcess ---
    private func stopListeningAndProcess(recognizedText: String) {
        speechRecognizers.stopRecording()
        print("DEBUG: Entered stopListeningAndProcess with text: '\(recognizedText)'") // <<< DEBUG LOG

         guard !recognizedText.isEmpty else {
            print("DEBUG: No speech detected, calling handleEmptyRecognition.") // <<< DEBUG LOG
            handleEmptyRecognition()
            return
        }

        let command = recognizedText.lowercased()
        let needsImage = command.contains("describe") || command.contains("what") || command.contains("read") || command.contains("locate") || command.contains("find") || command.contains("point") || command.contains("see") || command.contains("look") || command.contains("picture")
        print("DEBUG: Determined needsImage = \(needsImage) for command: '\(command)'") // <<< DEBUG LOG

        withAnimation(.easeInOut(duration: 0.3)) {
             isProcessing = true
             updateButtonStatusText()
        }

        if needsImage {
             withAnimation { buttonStatusText = "Capturing Image..." }
             print("DEBUG: Calling startCameraAndCaptureSingleFrame...") // <<< DEBUG LOG
             startCameraAndCaptureSingleFrame { image in
                  // <<< DEBUG LOG inside completion handler
                  print("DEBUG: startCameraAndCaptureSingleFrame completion handler called.")
                  if let capturedImage = image {
                       print("DEBUG: Image captured successfully, calling sendRequestToServer.") // <<< DEBUG LOG
                      self.lastCapturedImage = capturedImage // Store image if needed elsewhere
                      sendRequestToServer(query: recognizedText, image: capturedImage)
                  } else {
                       print("DEBUG: Image capture failed (image is nil), handling error.") // <<< DEBUG LOG
                       let cameraError = NSError(domain: "CameraError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to capture image. Please ensure camera access is enabled."])
                      handleProcessingError(error: cameraError)
                  }
             }
        } else {
             print("DEBUG: Command does not need image, handling as text-only/error.") // <<< DEBUG LOG
             let textOnlyError = NSError(domain: "AppLogicError", code: -1, userInfo: [NSLocalizedDescriptionKey: "This command doesn't seem to require an image, and text-only requests might not be fully supported yet."])
             handleProcessingError(error: textOnlyError)
        }
    }

     // --- MODIFIED startCameraAndCaptureSingleFrame ---
     private func startCameraAndCaptureSingleFrame(completion: @escaping (UIImage?) -> Void) {
         print("DEBUG: Inside startCameraAndCaptureSingleFrame") // <<< DEBUG LOG
         var frameReceived = false
         // Use weak self in capture block to avoid retain cycles if necessary
         cameraManager.startCapturingFrames { [weak cameraManager] capturedImage in
              // Use DispatchQueue.main to ensure UI updates (if any) happen on main thread
              DispatchQueue.main.async {
                   // Ensure this block runs only once
                   guard !frameReceived else {
                        print("DEBUG: Camera frame received, but completion already called.") // <<< DEBUG LOG
                        return
                   }
                   frameReceived = true
                   print("DEBUG: CameraManager captured frame callback executing.") // <<< DEBUG LOG
                   cameraManager?.stop() // Stop capturing immediately after getting one frame
                   print("DEBUG: Camera stopped.") // <<< DEBUG LOG
                   if let img = capturedImage {
                        print("DEBUG: Captured image is valid (not nil). Calling completion.") // <<< DEBUG LOG
                        completion(img)
                   } else {
                        print("DEBUG: Captured image is nil. Calling completion with nil.") // <<< DEBUG LOG
                        completion(nil)
                   }
              }
         }

         // Timeout logic
         DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak cameraManager] in
              // Check if frame has already been received
              guard !frameReceived else { return }
              frameReceived = true // Mark as timed out
              print("DEBUG: Camera frame capture TIMEOUT.") // <<< DEBUG LOG
              cameraManager?.stop() // Stop capturing on timeout
               print("DEBUG: Camera stopped due to timeout.") // <<< DEBUG LOG
              completion(nil) // Call completion with nil due to timeout
         }
     }

    private func handleEmptyRecognition() {
         print("No speech detected."); generateNotificationHaptic(.warning)
         withAnimation(.easeInOut(duration: 0.3)) { buttonStatusText = "No Speech Detected"; isListening = false; isProcessing = false; isSpeaking = false; updatePulseState() }
         DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { if self.buttonStatusText == "No Speech Detected" { withAnimation { self.updateButtonStatusText() } } }
     }

    // --- MODIFIED sendRequestToServer ---
    private func sendRequestToServer(query: String, image: UIImage?) {
          print("DEBUG: Entered sendRequestToServer.") // <<< DEBUG LOG
          withAnimation(.easeInOut(duration: 0.3)) {
              isProcessing = true
              isListening = false
              isSpeaking = false
              buttonStatusText = "Processing..."
              serverResponseText = ""
              errorMessage = nil
              updatePulseState()
          }

          let command = query.lowercased()
          let needsImage = command.contains("describe") || command.contains("what") || command.contains("read") || command.contains("locate") || command.contains("find") || command.contains("point") || command.contains("see") || command.contains("look") || command.contains("picture")

          print("DEBUG: sendRequestToServer - needsImage=\(needsImage), image provided=\(image != nil)") // <<< DEBUG LOG

          // Guard adjusted slightly for clarity - ENSURE actualImage is checked correctly
          guard let actualImage = image else {
                // This case should only be hit if image is nil.
                // We already determined if image was needed earlier. If it was needed but is nil, this error is correct.
                print("DEBUG: sendRequestToServer - image is nil. Handling error (assuming image was required).") // <<< DEBUG LOG
                handleProcessingError(error: NSError(domain: "AppLogicError", code: -5, userInfo: [NSLocalizedDescriptionKey: "Image required but was not captured successfully."]))
               return
          }

          // --- Make the API Call ---
           print("DEBUG: Calling apiService.processQueryWithImage...") // <<< DEBUG LOG
           apiService.processQueryWithImage(query: query, image: actualImage) { result in
               // <<< DEBUG LOG inside completion handler
               print("DEBUG: apiService.processQueryWithImage completion handler called.")
               DispatchQueue.main.async {
                   switch result {
                   case .success(let responseText):
                       print("DEBUG: API call successful.") // <<< DEBUG LOG
                       self.handleSuccessfulResponse(responseText)
                   case .failure(let error):
                       print("DEBUG: API call failed. Error: \(error.localizedDescription)") // <<< DEBUG LOG
                       self.handleProcessingError(error: error)
                   }
                   // Ensure processing state is turned off after handling response
                    withAnimation(.easeInOut(duration: 0.3)) {
                         self.isProcessing = false
                         self.updatePulseState()
                         // Status text update moved to specific handlers
                    }
               }
           }
           // --- End API Call ---
    }


    // --- MODIFIED handleSuccessfulResponse ---
    private func handleSuccessfulResponse(_ text: String) {
        print("DEBUG: Entered handleSuccessfulResponse.") // <<< DEBUG LOG
        generateNotificationHaptic(.success)
        withAnimation(.easeInOut(duration: 0.4)) {
            errorMessage = nil
            serverResponseText = text
            isSpeaking = true // Set speaking state FIRST
            buttonStatusText = "Speaking..." // Update status text
            updatePulseState()
        }

        print("Speaking response with voice: \(selectedVoice)")
        AudioSessionManager.shared.activate()

        ttsManager.speak(text, voice: selectedVoice) {
            DispatchQueue.main.async {
                 print("DEBUG: TTS Playback completed callback.") // <<< DEBUG LOG
                 if self.isSpeaking {
                      withAnimation(.easeInOut(duration: 0.3)) {
                           self.isSpeaking = false
                           self.updatePulseState()
                           self.updateButtonStatusText() // Reset to "Tap to Speak"
                      }
                 }
            }
        }
    }

     // --- MODIFIED handleProcessingError ---
     private func handleProcessingError(error: Error) {
         // <<< DEBUG LOG
         print("DEBUG: Entered handleProcessingError. Error: \(error.localizedDescription)")

         var displayMessage: String
         // ... (error message formatting logic remains the same) ...
          if let apiError = error as? APIService.APIServiceError {
              switch apiError {
              case .invalidURL: displayMessage = "Error: Cannot reach server (Invalid URL)."
              case .failedToCreateRequestData, .failedToEncodeImage: displayMessage = "Error: Could not prepare request."
              case .networkError(let underlyingError):
                  let nsError = underlyingError as NSError
                   if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCannotConnectToHost { displayMessage = "Cannot connect to server. Check IP & Wi-Fi." }
                   else if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCannotFindHost { displayMessage = "Cannot find server. Check IP address." }
                   else if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut { displayMessage = "Request timed out. Server may be busy." }
                   else { displayMessage = "Network Error. Check connection." }
                   print("Underlying network error: \(underlyingError.localizedDescription)")
              case .invalidResponseData, .noDataReceived: displayMessage = "Error: Received invalid data from server."
              case .serverError(let message, let code):
                   if message.contains("requires an image") { displayMessage = "Error: This request needs an image." }
                   else if message.contains("Invalid image file") { displayMessage = "Error: Invalid image format."}
                   else { displayMessage = "Server Error (\(code)). Please try again." }
                   print("Raw server error message: \(message)")
              case .jsonParsingError: displayMessage = "Error: Could not understand server response."
              }
          } else { displayMessage = error.localizedDescription } // Use localized description for other errors (like CameraError)

         print("Processing error display message: \(displayMessage)") // Log the message shown to user
         generateNotificationHaptic(.error)
         withAnimation(.easeInOut(duration: 0.3)) {
              errorMessage = displayMessage
              isProcessing = false
              isListening = false
              isSpeaking = false
              updatePulseState()
              buttonStatusText = "Error Occurred"
         }

         DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
              if self.errorMessage == displayMessage {
                  withAnimation {
                      self.errorMessage = nil
                       if self.buttonStatusText == "Error Occurred" {
                            self.updateButtonStatusText()
                       }
                  }
              }
         }
     }
}
