import SwiftUI

struct PermissionDeniedView: View {
    let onRetry: () -> Void
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color("#2E3192"), Color("#1BFFFF"), Color("#4682b4")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                Text("Permissions Required")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                Text("We need camera, microphone, and speech access. Enable them in Settings.")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                Button(action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    onRetry()
                }) {
                    Text("Open Settings")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 40)
                        .background(Color.blue)
                        .cornerRadius(30)
                }
                
                Spacer()
            }
            .padding()
        }
    }
}
