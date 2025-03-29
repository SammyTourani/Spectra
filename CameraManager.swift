import AVFoundation
import UIKit

class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var lastFrameTime: TimeInterval = 0
    private var frameCallback: ((UIImage) -> Void)?
    var fps: Double = 2 // Reduced to lower server load
    
    override init() {
        super.init()
        setupCaptureSession()
    }
    
    private func setupCaptureSession() {
        captureSession.sessionPreset = .medium
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(input) else { return }
        captureSession.addInput(input)
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
    }
    
    func startCapturingFrames(callback: @escaping (UIImage) -> Void) {
        self.frameCallback = callback
        
        sessionQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    func start() {
        // For backward compatibility
        startCapturingFrames { _ in }
    }
    
    func stop() {
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
        frameCallback = nil
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastFrameTime >= 1.0 / fps else { return }
        lastFrameTime = currentTime
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let cgImage = CIContext().createCGImage(CIImage(cvPixelBuffer: imageBuffer), from: CIImage(cvPixelBuffer: imageBuffer).extent) else { return }
        
        let image = UIImage(cgImage: cgImage)
        
        // Send the image to callback on main thread if available
        if let callback = frameCallback {
            DispatchQueue.main.async {
                callback(image)
            }
        }
    }
}
