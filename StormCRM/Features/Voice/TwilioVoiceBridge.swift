#if canImport(TwilioVoice)
import Foundation
import TwilioVoice

@MainActor
final class TwilioVoiceBridge: NSObject {
    static let shared = TwilioVoiceBridge()

    private var activeCall: Call?
    var onStatusChange: ((String) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onError: ((String) -> Void)?

    private override init() {
        super.init()
    }

    var isInCall: Bool { activeCall != nil }

    func connect(accessToken: String, params: [String: String]) {
        disconnect()
        let options = ConnectOptions(accessToken: accessToken) { builder in
            builder.params = params
        }
        activeCall = TwilioVoiceSDK.connect(options: options, delegate: self)
        onStatusChange?("Connecting…")
    }

    func disconnect() {
        activeCall?.disconnect()
        activeCall = nil
    }

    func setMuted(_ muted: Bool) {
        activeCall?.isMuted = muted
    }
}

extension TwilioVoiceBridge: CallDelegate {
    nonisolated func callDidConnect(call: Call) {
        Task { @MainActor in
            onStatusChange?("On call")
            onConnected?()
        }
    }

    nonisolated func callDidFailToConnect(call: Call, error: Error) {
        Task { @MainActor in
            onError?(error.localizedDescription)
            onStatusChange?("Call failed")
            activeCall = nil
            onDisconnected?()
        }
    }

    nonisolated func callDidDisconnect(call: Call, error: Error?) {
        Task { @MainActor in
            if let error {
                onError?(error.localizedDescription)
            }
            onStatusChange?("Ready")
            activeCall = nil
            onDisconnected?()
        }
    }
}
#endif
