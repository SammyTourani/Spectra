import Foundation
import UIKit
import AVFoundation

class APIService {
    static let shared = APIService()
    
    private let baseURL: String
    private let port: Int
    
    private var audioPlayer: AVAudioPlayer?
    
    init(serverAddress: String = "172.18.179.5", port: Int = 8000) {
        self.baseURL = serverAddress
        self.port = port
    }
    
    // MARK: - API Methods
    
    func sendSpeechCommand(_ text: String, completion: @escaping (Result<String, Error>) -> Void) {
        print("Sending speech command: \(text)")
        
        guard let url = URL(string: "http://\(baseURL):\(port)/speech") else {
            let error = NSError(domain: "APIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            completion(.failure(error))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let parameters = ["query": text]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        } catch {
            completion(.failure(error))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Network error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let data = data,
                  let responseString = String(data: data, encoding: .utf8) else {
                let error = NSError(domain: "APIService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response data"])
                completion(.failure(error))
                return
            }
            
            print("Received response: \(responseString)")
            completion(.success(responseString))
        }
        
        task.resume()
    }
    
    func sendImage(_ image: UIImage, completion: @escaping (Result<(text: String, audioData: Data?), Error>) -> Void) {
        print("Preparing to send image")
        
        guard let url = URL(string: "http://\(baseURL):\(port)/process-image") else {
            let error = NSError(domain: "APIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            completion(.failure(error))
            return
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            let error = NSError(domain: "APIService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to JPEG"])
            completion(.failure(error))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.uploadTask(with: request, from: imageData) { data, response, error in
            if let error = error {
                print("Image upload error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                let error = NSError(domain: "APIService", code: 4, userInfo: [NSLocalizedDescriptionKey: "No data received"])
                completion(.failure(error))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let recognizedText = json["recognized_text"] as? String {
                    
                    var audioData: Data? = nil
                    if let audioBase64 = json["audio_base64"] as? String {
                        audioData = Data(base64Encoded: audioBase64)
                    }
                    
                    print("Received text: \(recognizedText)")
                    completion(.success((text: recognizedText, audioData: audioData)))
                } else {
                    let error = NSError(domain: "APIService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"])
                    completion(.failure(error))
                }
            } catch {
                print("JSON parsing error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
    
    // Helper method to play audio data
    func playAudioData(_ audioData: Data) {
        do {
            // Stop any current playback
            audioPlayer?.stop()
            
            // Create and play new audio
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.prepareToPlay()
            
            AudioSessionManager.shared.activate()
            audioPlayer?.play()
        } catch {
            print("Error playing audio: \(error.localizedDescription)")
        }
    }
}
