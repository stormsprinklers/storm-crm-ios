import AVFoundation
import Foundation

enum StormAiMediaPermissions {
    static func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    static func requestCamera() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    /// Mic always; camera when video mode is on.
    static func requestForRealtime(video: Bool) async -> String? {
        let micOk = await requestMicrophone()
        if !micOk {
            return "Microphone access is required for Storm AI voice."
        }
        if video {
            let camOk = await requestCamera()
            if !camOk {
                return "Camera access is required for Storm AI video."
            }
        }
        return nil
    }
}
