import SwiftUI
import AVFoundation

struct HomeView: View {
    @ObservedObject private var speechRecognizers = SpeechRecognizers()
    private let cameraManager = CameraManager()
    
    @State private var isListening = false
    @State private var isSpeaking = false
    @State private var finalRecognizedText = ""
    @State private var serverResponseText = ""
    @State private var buttonStatusText = "Awaiting command"
    
    var body: some View {
        ZStack {
            Color(red: 175/255, green: 196/255, blue: 214/255)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                Text("Spectra")
                    .font(.largeTitle)
                    .foregroundColor(.black)
                    .padding(.bottom, 20)
                
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .background(Circle().fill(Color.blue))
                    .frame(width: 100, height: 100)
                    .scaleEffect(isSpeaking ? 1.4 : 1.0)
                    .animation(
                        isSpeaking ? Animation.easeInOut(duration: 0.75).repeatForever(autoreverses: true) : .default,
                        value: isSpeaking
                    )
                    .onTapGesture {
                        handleTapGesture()
                    }
                
                Text(buttonStatusText)
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .padding(.top, 30)
                
                Spacer()
                
                Text(serverResponseText.isEmpty ? "Response will appear here" : serverResponseText)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .padding(.horizontal, 40)
                
                Spacer()
            }
        }
    }
    
    private func handleTapGesture() {
        isListening.toggle()
        if isListening {
            buttonStatusText = "Listening..."
            finalRecognizedText = ""
            serverResponseText = ""
            speechRecognizers.startRecording { recognizedText in
                finalRecognizedText = recognizedText
                isSpeaking = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isSpeaking = false
                }
            }
        } else {
            buttonStatusText = "Processing request"
            speechRecognizers.stopRecording()
            sendRecognizedTextToServer(finalRecognizedText)
        }
    }
    
    private func sendRecognizedTextToServer(_ recognizedText: String) {
        guard let url = URL(string: "http://172.18.179.5:8000/speech") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let parameters = ["query": recognizedText]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: parameters)
            request.httpBody = jsonData
        } catch {
            print("Error making JSON: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                print("Request error: \(error)")
                return
            }
            guard let data = data, let responseString = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                serverResponseText = responseString
                if responseString == "Ok, I will begin reading the text, please point your camera towards it" {
                    cameraManager.start()
                }
            }
        }.resume()
    }
}
