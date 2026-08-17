import AVFoundation
import SwiftUI
import UIKit

/// Full-FPS local camera preview. Frames are captured as stills on demand — not streamed to OpenAI.
final class StormAiCameraController: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var isRunning = false
    @Published var lastError: String?

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "storm.ai.camera")
    private var continuation: CheckedContinuation<Data?, Never>?

    func start() async -> Bool {
        let allowed = await StormAiMediaPermissions.requestCamera()
        guard allowed else {
            await MainActor.run { lastError = "Camera access denied" }
            return false
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: false)
                    return
                }
                self.configureAndStart()
                continuation.resume(returning: self.session.isRunning)
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    func captureJPEG(maxEdge: CGFloat = 1280, quality: CGFloat = 0.82) async -> Data? {
        let data: Data? = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                if self.continuation != nil {
                    continuation.resume(returning: nil)
                    return
                }
                guard self.session.isRunning else {
                    continuation.resume(returning: nil)
                    return
                }
                self.continuation = continuation
                let settings = AVCapturePhotoSettings()
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
        guard let data, let image = UIImage(data: data) else { return nil }
        return image.stormAiResizedJPEG(maxEdge: maxEdge, quality: quality)
    }

    private func configureAndStart() {
        session.beginConfiguration()
        session.sessionPreset = .high

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            DispatchQueue.main.async {
                self.lastError = "Camera unavailable"
            }
            session.commitConfiguration()
            return
        }

        session.addInput(input)
        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(photoOutput)
        if let connection = photoOutput.connection(with: .video) {
            applyPortraitOrientation(to: connection)
        }
        session.commitConfiguration()
        session.startRunning()
        DispatchQueue.main.async {
            self.isRunning = self.session.isRunning
            self.lastError = nil
        }
    }

    private func applyPortraitOrientation(to connection: AVCaptureConnection) {
        if #available(iOS 17.0, *) {
            let angle: CGFloat = 90
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
}

extension StormAiCameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        let cont = continuation
        continuation = nil
        cont?.resume(returning: data)
    }
}

struct StormAiCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.attach(session: session)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.attach(session: session)
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        func attach(session: AVCaptureSession) {
            if previewLayer.session !== session {
                previewLayer.session = session
            }
            previewLayer.videoGravity = .resizeAspectFill
            // Re-bind on the next run loop so the layer is in the hierarchy when mid-call video starts.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.previewLayer.session !== session {
                    self.previewLayer.session = session
                }
                if let connection = self.previewLayer.connection, connection.isEnabled == false {
                    connection.isEnabled = true
                }
            }
        }
    }
}

extension UIImage {
    func stormAiResizedJPEG(maxEdge: CGFloat, quality: CGFloat) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxEdge ? maxEdge / longest : 1
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
