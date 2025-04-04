import AVFoundation
import Foundation
import UIKit

class AzureTTSManager: ObservableObject {
    // Singleton instance
    static let shared = AzureTTSManager()
    
    private let apiKey: String
    private let region: String
    private let baseURL: String
    
    // Priority speech protection
    private var prioritySpeechInProgress = false
    private var prioritySpeechID: String? = nil
    
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
    private var currentPlaybackDelegate: PlaybackDelegate?
    private let playerQueue = DispatchQueue(label: "com.spectra.tts.player", qos: .userInitiated)
    
    // Pending requests management
    private var pendingSpeechTasks: [String: URLSessionDataTask] = [:]
    private let requestQueue = DispatchQueue(label: "com.spectra.tts.request", qos: .userInitiated)
    
    // Make init private to enforce singleton pattern
    private init() {
        self.apiKey = "BcZtnvJFdIxg9rexNdQUwOQYFay9YaGZMPUkBKPfgtE8VBEbQIgJJQQJ99BCACBsN54XJ3w3AAAYACOGpSuV"
        self.region = "canadacentral"
        self.baseURL = "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1"
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryPressure),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    // Method to start priority speech
    func speakWithPriority(_ text: String, voice: String, completion: @escaping () -> Void) {
        print("AzureTTSManager: Starting priority speech: \(text)")
        prioritySpeechInProgress = true
        let speechID = UUID().uuidString
        prioritySpeechID = speechID
        
        speak(text, voice: voice) {
            if self.prioritySpeechID == speechID {
                self.prioritySpeechInProgress = false
                self.prioritySpeechID = nil
            }
            completion()
        }
        
        // Safety cleanup in case callback never fires
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if self.prioritySpeechID == speechID {
                self.prioritySpeechInProgress = false
                self.prioritySpeechID = nil
            }
        }
    }
    
    func prefetchSpeech(_ text: String, voice: String) {
        let cacheKey = "\(text)_\(voice)"
        
        // Only prefetch if not already cached
        if audioCache[cacheKey] == nil {
            print("AzureTTSManager: Prefetching speech: \(text)")
            
            // Begin request but don't need to track completion
            requestQueue.async { [weak self] in
                if let existingTask = self?.pendingSpeechTasks[cacheKey] {
                    print("AzureTTSManager: Already fetching this speech")
                    return
                }
                
                self?.requestSpeech(text: text, voice: voice, cacheKey: cacheKey) {
                    print("AzureTTSManager: Prefetch complete for: \(cacheKey)")
                }
            }
        } else {
            print("AzureTTSManager: Speech already cached: \(cacheKey)")
        }
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
        
        let ssml = """
        <speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>
            <voice name='\(voice)'>
                <prosody rate="0.9">\(text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;"))</prosody>
            </voice>
        </speak>
        """
        
        request.httpBody = ssml.data(using: .utf8)
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            self?.requestQueue.async {
                self?.pendingSpeechTasks.removeValue(forKey: cacheKey)
            }
            
            if let error = error {
                if (error as NSError).code != NSURLErrorCancelled {
                    print("AzureTTSManager: Request error: \(error.localizedDescription)")
                }
                DispatchQueue.main.async { completion() }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("AzureTTSManager: Invalid response from server")
                DispatchQueue.main.async { completion() }
                return
            }
            
            print("AzureTTSManager: Received response with status code: \(httpResponse.statusCode)")
            
            guard (200...299).contains(httpResponse.statusCode),
                  let data = data, !data.isEmpty else {
                print("AzureTTSManager: Response error - Status code: \(httpResponse.statusCode)")
                DispatchQueue.main.async { completion() }
                return
            }
            
            print("AzureTTSManager: Successfully received audio data of size: \(data.count) bytes")
            
            self?.cacheAudioData(data, forKey: cacheKey)
            self?.playAudioData(data, completion: completion)
        }
        
        requestQueue.async { [weak self] in
            self?.pendingSpeechTasks[cacheKey] = task
            task.resume()
            print("AzureTTSManager: Request task started for: \(cacheKey)")
        }
    }
    
    private func cacheAudioData(_ data: Data, forKey key: String) {
        requestQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.audioCache[key] = data
            
            if self.audioCache.count > self.maxCacheEntries {
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
            
            // Ensure audio session is activated for playback
            AudioSessionManager.shared.activate()
            AudioSessionManager.shared.markAudioPlaybackStarted()
            
            // Clear existing references
            self.currentPlayer = nil
            self.currentPlaybackDelegate = nil
            
            do {
                // Create and configure audio player
                let player = try AVAudioPlayer(data: data)
                player.prepareToPlay()
                
                // Create and store delegate with strong reference
                let delegate = PlaybackDelegate { [weak self] success in
                    print("AzureTTSManager: Playback finished with success: \(success)")
                    
                    // Mark audio playback as ended
                    AudioSessionManager.shared.markAudioPlaybackEnded()
                    
                    // Clear the delegate reference
                    self?.currentPlaybackDelegate = nil
                    self?.currentPlayer = nil
                    
                    DispatchQueue.main.async { completion() }
                }
                
                // Store strong references
                self.currentPlaybackDelegate = delegate
                self.currentPlayer = player
                player.delegate = delegate
                
                // Start playback
                if player.play() {
                    print("AzureTTSManager: Playback started successfully")
                } else {
                    print("AzureTTSManager: Playback failed to start")
                    AudioSessionManager.shared.markAudioPlaybackEnded()
                    self.currentPlaybackDelegate = nil
                    self.currentPlayer = nil
                    DispatchQueue.main.async { completion() }
                }
                
            } catch {
                print("AzureTTSManager: Audio player error: \(error)")
                AudioSessionManager.shared.markAudioPlaybackEnded()
                self.currentPlaybackDelegate = nil
                self.currentPlayer = nil
                DispatchQueue.main.async { completion() }
            }
        }
    }
    
    func cancelAllSpeech() {
        // Check if priority speech is in progress
        if prioritySpeechInProgress {
            print("AzureTTSManager: Priority speech in progress, cancellation blocked")
            return
        }
        
        requestQueue.async { [weak self] in
            self?.pendingSpeechTasks.values.forEach { $0.cancel() }
            self?.pendingSpeechTasks.removeAll()
            print("AzureTTSManager: Cancelled all pending speech tasks")
        }
        
        playerQueue.async { [weak self] in
            if let player = self?.currentPlayer, player.isPlaying {
                print("AzureTTSManager: Stopping current playback on cancel")
                player.stop()
                
                // Mark audio playback as ended
                AudioSessionManager.shared.markAudioPlaybackEnded()
            }
            self?.currentPlayer = nil
            self?.currentPlaybackDelegate = nil
        }
    }
    
    @objc private func handleMemoryPressure() {
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

private class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    private let completion: (Bool) -> Void
    
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
