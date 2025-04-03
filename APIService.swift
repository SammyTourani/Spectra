// [[[cog
// import cog
// cog.outl(f'// -*- coding: utf-8 -*-')
// ]]]
// -*- coding: utf-8 -*-
// [[[end]]]
import Foundation
import UIKit
// import AVFoundation // No longer needed here for audioPlayer

class APIService {
    static let shared = APIService()

    // =======================================================================
    // Using IP Address provided by the user
    private let serverIP: String = "172.17.96.86"
    // =======================================================================
    private let port: Int = 8000
    private var baseURL: String { "http://\(serverIP):\(port)" }

    private init() {}

    // MARK: - Error Types
    enum APIServiceError: Error {
        case invalidURL
        case failedToCreateRequestData
        case failedToEncodeImage
        case networkError(Error)
        case invalidResponseData
        case serverError(String, Int) // Include status code
        case jsonParsingError(Error)
        case noDataReceived
    }

    // MARK: - Main API Method
    func processQueryWithImage(query: String, image: UIImage, completion: @escaping (Result<String, APIServiceError>) -> Void) {
        // <<< DEBUG LOG
        print("DEBUG: APIService.processQueryWithImage called with query: '\(query)', image size: \(image.size)")
        // <<< END DEBUG LOG

        print("APIService: Sending query='\(query)' with image...")

        // Construct URL making sure baseURL is valid
        guard let url = URL(string: "\(baseURL)/process") else {
            print("APIService: Error - Invalid URL constructed: \(baseURL)/process")
            completion(.failure(.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"query\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(query)\r\n".data(using: .utf8)!)

        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(.failure(.failedToEncodeImage))
            return
        }
        let filename = "image.jpg"
        let mimetype = "image/jpeg"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimetype)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        request.timeoutInterval = 60 // Keep timeout generous for now

        print("APIService: Sending request to \(url.absoluteString)...") // Log the exact URL being requested

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("APIService: Network error: \(error.localizedDescription)")
                let nsError = error as NSError
                var detailedError: Error = error
                // Provide specific feedback for connection errors
                if nsError.domain == NSURLErrorDomain {
                     if nsError.code == NSURLErrorCannotConnectToHost || nsError.code == NSURLErrorCannotFindHost {
                           print("APIService: Specific Error - Cannot connect/find host. Verify IP address (\(self.serverIP)) and ensure the server is running and accessible on the network.")
                           detailedError = APIServiceError.networkError(NSError(domain: nsError.domain, code: nsError.code, userInfo: [NSLocalizedDescriptionKey: "Could not find or connect to the server at \(self.serverIP):\(self.port). Please double-check the IP, ensure the server is running on your Mac, and that both devices are on the same Wi-Fi."]))
                     } else if nsError.code == NSURLErrorTimedOut {
                           detailedError = APIServiceError.networkError(NSError(domain: nsError.domain, code: nsError.code, userInfo: [NSLocalizedDescriptionKey: "Request timed out connecting to \(self.serverIP). Server might be busy or unreachable."]))
                     } else if nsError.code == NSURLErrorNotConnectedToInternet {
                           detailedError = APIServiceError.networkError(NSError(domain: nsError.domain, code: nsError.code, userInfo: [NSLocalizedDescriptionKey: "The iPhone is not connected to the internet (or the Wi-Fi network)."]))
                     } else if nsError.code == NSURLErrorNetworkConnectionLost {
                         detailedError = APIServiceError.networkError(NSError(domain: nsError.domain, code: nsError.code, userInfo: [NSLocalizedDescriptionKey: "The network connection was lost."]))
                     }
                }
                 let finalError = (detailedError as? APIServiceError) ?? .networkError(detailedError)
                 DispatchQueue.main.async { completion(.failure(finalError)) }
                return
            }

             guard let httpResponse = response as? HTTPURLResponse else {
                 print("APIService: Invalid response from server (not HTTP).")
                 DispatchQueue.main.async { completion(.failure(.invalidResponseData)) }
                 return
             }

             print("APIService: Received HTTP status code: \(httpResponse.statusCode)")

             guard let data = data, !data.isEmpty else {
                 print("APIService: No data received from server.")
                  DispatchQueue.main.async { completion(.failure(.noDataReceived)) }
                 return
             }

             guard (200...299).contains(httpResponse.statusCode) else {
                 var errorMessage = "Server error occurred."
                  if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let detail = errorJson["detail"] as? String {
                      errorMessage = detail
                  } else if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let errTxt = errorJson["error"] as? String {
                      errorMessage = errTxt
                  } else if let responseString = String(data: data, encoding: .utf8), !responseString.isEmpty {
                      errorMessage = responseString
                  }
                  print("APIService: Server returned error (\(httpResponse.statusCode)): \(errorMessage)")
                  DispatchQueue.main.async { completion(.failure(.serverError(errorMessage, httpResponse.statusCode))) }
                  return
             }

             do {
                 if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                      if let errMsg = json["error"] as? String {
                           print("APIService: Server returned success code (\(httpResponse.statusCode)) but JSON contains error: \(errMsg)")
                           DispatchQueue.main.async { completion(.failure(.serverError(errMsg, httpResponse.statusCode))) }
                           return
                      }
                     guard let recognizedText = json["recognized_text"] as? String else {
                         print("APIService: Error - 'recognized_text' missing or not a string in JSON.")
                          if let responseString = String(data: data, encoding: .utf8) { print("APIService: Raw JSON response: \(responseString)") }
                          DispatchQueue.main.async { completion(.failure(.invalidResponseData)) }
                         return
                     }
                     print("APIService: Successfully parsed response. Text length: \(recognizedText.count)")
                     DispatchQueue.main.async { completion(.success(recognizedText)) }
                 } else {
                      print("APIService: Error - Failed to parse JSON or JSON was not a dictionary.")
                       if let responseString = String(data: data, encoding: .utf8) { print("APIService: Raw non-JSON response: \(responseString)") }
                      DispatchQueue.main.async { completion(.failure(.invalidResponseData)) }
                 }
             } catch {
                 print("APIService: JSON parsing error: \(error.localizedDescription)")
                  if let responseString = String(data: data, encoding: .utf8) { print("APIService: Raw response causing JSON error: \(responseString)") }
                 DispatchQueue.main.async { completion(.failure(.jsonParsingError(error))) }
             }
        }
        task.resume()
    }
}
