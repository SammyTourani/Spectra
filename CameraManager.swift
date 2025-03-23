import AVFoundation
import UIKit

class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var lastFrameTime: TimeInterval = 0
    var fps: Double = 10
    
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
    
    func start() {
        sessionQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    func stop() {
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastFrameTime >= 1.0 / fps else { return }
        lastFrameTime = currentTime
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let cgImage = CIContext().createCGImage(CIImage(cvPixelBuffer: imageBuffer), from: CIImage(cvPixelBuffer: imageBuffer).extent),
              let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8),
              let url = URL(string: "http://172.18.179.5:8000/process-image") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        URLSession.shared.uploadTask(with: request, from: jpegData) { _, _, error in
            if let error = error { print("Camera upload error: \(error)") }
        }.resume()
    }
}
