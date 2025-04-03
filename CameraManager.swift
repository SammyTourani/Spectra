import AVFoundation
import UIKit

class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var lastFrameTime: TimeInterval = 0
    // --- MODIFIED: Callback now expects an Optional UIImage? ---
    private var frameCallback: ((UIImage?) -> Void)?
    var fps: Double = 2 // Reduced to lower server load

    override init() {
        super.init()
        setupCaptureSession()
    }

    private func setupCaptureSession() {
        captureSession.sessionPreset = .medium // Use medium preset for better performance balance
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), // Prefer back camera
              let input = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(input) else {
            print("CameraManager Error: Failed to get camera input.")
            return
        }
        captureSession.addInput(input)

        let videoOutput = AVCaptureVideoDataOutput()
        // Specify pixel format for efficiency if needed (e.g., kCVPixelFormatType_32BGRA)
        // videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoOutput.alwaysDiscardsLateVideoFrames = true // Discard late frames to reduce latency
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            // Set video orientation if necessary (usually handled by UI)
            // if let connection = videoOutput.connection(with: .video) {
            //    if connection.isVideoOrientationSupported {
            //        connection.videoOrientation = .portrait
            //    }
            // }
        } else {
             print("CameraManager Error: Could not add video output.")
        }
    }

    // --- MODIFIED: Callback signature now takes UIImage? ---
    func startCapturingFrames(callback: @escaping (UIImage?) -> Void) {
        // Ensure callback is set on the main queue for safety if needed later,
        // but image processing happens on sessionQueue.
        // The actual call to the callback is dispatched to main in captureOutput.
        self.frameCallback = callback

        // Avoid starting if already running
        guard !captureSession.isRunning else {
            print("CameraManager: Capture session already running.")
            return
        }

        sessionQueue.async { [weak self] in
            print("CameraManager: Starting capture session.")
            self?.captureSession.startRunning()
            self?.lastFrameTime = 0 // Reset frame timer when starting
        }
    }

    // Kept for backward compatibility if needed, but points to the new one
    func start() {
        startCapturingFrames { _ in }
    }

    func stop() {
        // Avoid stopping if already stopped
        guard captureSession.isRunning else {
            print("CameraManager: Capture session already stopped.")
            return
        }
        sessionQueue.async { [weak self] in
             print("CameraManager: Stopping capture session.")
            self?.captureSession.stopRunning()
            // It's safer to nil out the callback here after stopping
             DispatchQueue.main.async {
                 self?.frameCallback = nil
             }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let currentTime = CACurrentMediaTime()
        // Ensure enough time has passed since the last frame to respect FPS limit
        guard currentTime - lastFrameTime >= 1.0 / fps else { return }

        // Check if a callback exists before processing the frame
        guard let callback = self.frameCallback else {
            // If no callback is set, no need to process the frame
            // print("CameraManager: No callback set, skipping frame processing.")
             return
        }

        lastFrameTime = currentTime // Update last frame time only when processing

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("CameraManager Error: Could not get image buffer from sample buffer.")
            // --- MODIFIED: Call back with nil on error ---
            DispatchQueue.main.async { callback(nil) }
            return
        }

        // Create CIImage first
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)

        // Use a shared CIContext for efficiency
        let context = CIContext(options: nil) // Or use pre-created context

        // Create CGImage
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
             print("CameraManager Error: Could not create CGImage from CIImage.")
             // --- MODIFIED: Call back with nil on error ---
             DispatchQueue.main.async { callback(nil) }
            return
        }

        // Create UIImage (consider orientation if needed)
        let image = UIImage(cgImage: cgImage)

        // Send the image to callback on main thread
        // --- MODIFIED: Calls back with the valid, non-optional image ---
        // The callback itself expects UIImage?, so this is fine.
        DispatchQueue.main.async {
            callback(image)
        }
    }

     deinit {
          // Ensure session is stopped when CameraManager is deallocated
          if captureSession.isRunning {
               captureSession.stopRunning()
          }
          print("CameraManager deinitialized.")
     }
}
