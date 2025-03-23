import SwiftUI

@main
struct SpectraApp: App {
    init() {
        _ = AudioSessionManager.shared // Initialize audio session
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
