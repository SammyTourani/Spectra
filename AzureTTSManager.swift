import AVFoundation
import Foundation
import UIKit // Add UIKit import for UIApplication

class AzureTTSManager: ObservableObject {
    private let apiKey: String
    private let region: String
    private let baseURL: String
    
    // Cache for previously synthesized speech
    private var audioCache: [String: Data] = [:]
    private let maxCacheEntries = 20
    
    // Network session for requests
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()
    
    // Audio player management
    private var currentPlayer: AVAudioPlayer?
    private let playerQueue = DispatchQueue(label: "com.spectra.tts.player", qos: .userInitiated)
    
    // Pending requests management
    private var pendingSpeechTasks: [String: URLSessionDataTask] = [:]
    private let requestQueue = DispatchQueue(label: "com.spectra.tts.request", qos: .userInitiated)
    
    init(apiKey: String, region: String) {
        self.apiKey = apiKey
        self.region = region
        self.baseURL = "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1"
        
        // Register for memory pressure notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryPressure),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    func speak(_ text: String, voice: String, completion: @escaping () -> Void) {
        let cacheKey = "\(text)_\(voice)"
        
        print("AzureTTSManager: Attempting to speak: '\(text)' with voice: \(voice)")
        
        // First check if we have this speech already cached
        if let cachedAudio = audioCache[cacheKey] {
            print("AzureTTSManager: Using cached audio for: \(cacheKey)")
            playAudioData(cachedAudio, completion: completion)
            return
        }
        
        // Cancel any identical pending request
        requestQueue.async { [weak self] in
            if let existingTask = self?.pendingSpeechTasks[cacheKey] {
                print("AzureTTSManager: Cancelling existing task for: \(cacheKey)")
                existingTask.cancel()
                self?.pendingSpeechTasks.removeValue(forKey: cacheKey)
            }
            
            print("AzureTTSManager: Sending request to Azure TTS for: \(cacheKey)")
            self?.requestSpeech(text: text, voice: voice, cacheKey: cacheKey, completion: completion)
        }
    }
    
    private func requestSpeech(text: String, voice: String, cacheKey: String, completion: @escaping () -> Void) {
        guard let url = URL(string: baseURL) else {
            print("AzureTTSManager: Invalid Azure TTS URL")
            DispatchQueue.main.async { completion() }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.addValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.addValue("audio-16khz-128kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.addValue(UUID().uuidString, forHTTPHeaderField: "X-RequestId")
        
        // Prepare SSML document - using more efficient string concatenation
        let ssml = """
        <speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>
            <voice name='\(voice)'>
                <prosody rate="0.9">\(text.replacingOccurrences(of: "&", with: "&").replacingOccurrences(of: "<", with: "<").replacingOccurrences(of: ">", with: ">"))</prosody>
            </voice>
        </speak>
        """
        
        request.httpBody = ssml.data(using: .utf8)
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            // Remove from pending tasks
            self?.requestQueue.async {
                self?.pendingSpeechTasks.removeValue(forKey: cacheKey)
            }
            
            // Handle errors
            if let error = error {
                if (error as NSError).code != NSURLErrorCancelled {
                    print("AzureTTSManager: Request error: \(error.localizedDescription)")
                }
                DispatchQueue.main.async { completion() }
                return
            }
            
            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                print("AzureTTSManager: Invalid response from server")
                DispatchQueue.main.async { completion() }
                return
            }
            
            print("AzureTTSManager: Received response with status code: \(httpResponse.statusCode)")
            
            guard (200...299).contains(httpResponse.statusCode),
                  let data = data, !data.isEmpty else {
                print("AzureTTSManager: Response error - Status code: \(httpResponse.statusCode), Data: \(data?.count ?? 0) bytes")
                DispatchQueue.main.async { completion() }
                return
            }
            
            print("AzureTTSManager: Successfully received audio data of size: \(data.count) bytes")
            
            // Cache the audio data
            self?.cacheAudioData(data, forKey: cacheKey)
            
            // Play the audio
            self?.playAudioData(data, completion: completion)
        }
        
        // Store and start the task
        requestQueue.async { [weak self] in
            self?.pendingSpeechTasks[cacheKey] = task
            task.resume()
            print("AzureTTSManager: Request task started for: \(cacheKey)")
        }
    }
    
    private func cacheAudioData(_ data: Data, forKey key: String) {
        requestQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Add to cache
            self.audioCache[key] = data
            
            // Manage cache size
            if self.audioCache.count > self.maxCacheEntries {
                // Remove random entry when cache gets too large
                if let keyToRemove = self.audioCache.keys.randomElement() {
                    self.audioCache.removeValue(forKey: keyToRemove)
                }
            }
            print("AzureTTSManager: Cached audio data for key: \(key)")
        }
    }
    
    private func playAudioData(_ data: Data, completion: @escaping () -> Void) {
        playerQueue.async { [weak self] in
            guard let self = self else {
                print("AzureTTSManager: Self deallocated, calling completion")
                DispatchQueue.main.async { completion() }
                return
            }
            
            // Stop any current playback
            if let player = self.currentPlayer, player.isPlaying {
                print("AzureTTSManager: Stopping current playback")
                player.stop()
            }
            
            do {
                // Create and configure audio player
                let player = try AVAudioPlayer(data: data)
                player.prepareToPlay()
                self.currentPlayer = player
                
                // Set up completion handler
                let playbackCompletion: (Bool) -> Void = { success in
                    print("AzureTTSManager: Playback finished with success: \(success)")
                    DispatchQueue.main.async { completion() }
                }
                
                player.delegate = PlaybackDelegate(completion: playbackCompletion)
                
                // Start playback
                if player.play() {
                    print("AzureTTSManager: Playback started successfully")
                } else {
                    print("AzureTTSManager: Playback failed to start")
                    DispatchQueue.main.async { completion() }
                }
                
            } catch {
                print("AzureTTSManager: Audio player error: \(error)")
                DispatchQueue.main.async { completion() }
            }
        }
    }
    
    func cancelAllSpeech() {
        requestQueue.async { [weak self] in
            // Cancel all pending network requests
            guard let self = self else { return }
            for task in self.pendingSpeechTasks.values {
                task.cancel()
            }
            self.pendingSpeechTasks.removeAll()
            print("AzureTTSManager: Cancelled all pending speech tasks")
        }
        
        playerQueue.async { [weak self] in
            // Stop current playback
            if let player = self?.currentPlayer, player.isPlaying {
                print("AzureTTSManager: Stopping current playback on cancel")
                player.stop()
            }
            self?.currentPlayer = nil
        }
    }
    
    @objc private func handleMemoryPressure() {
        // Clear cache on memory pressure
        requestQueue.async { [weak self] in
            self?.audioCache.removeAll()
            print("AzureTTSManager: Cleared audio cache due to memory pressure")
        }
    }
    
    deinit {
        cancelAllSpeech()
        NotificationCenter.default.removeObserver(self)
        print("AzureTTSManager: Deinitialized")
    }
}

// Helper delegate class for audio player completion
private class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    let completion: (Bool) -> Void
    
    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        super.init()
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        completion(flag)
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        completion(false)
    }
}

// Extend to make it compatible with UIKit's URL loading system for background tasks
extension AzureTTSManager {
    func applicationWillEnterForeground() {
        // Refresh session if needed when app comes to foreground
        session.configuration.waitsForConnectivity = true
    }
    
    func applicationDidEnterBackground() {
        // Ensure background tasks can complete if needed
        session.configuration.waitsForConnectivity = false
    }
}
