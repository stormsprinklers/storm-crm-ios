import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// In-app calling via Twilio Voice iOS SDK (VoIP through CRM).
@MainActor
final class VoiceManager: ObservableObject {
    @Published var status = "Ready"
    @Published var lastError: String?
    @Published private(set) var isInCall = false
    @Published private(set) var isMuted = false
    @Published private(set) var activePhone: String?
    @Published private(set) var isIncoming = false

    private let apiClient: APIClient
    private let auth: AuthManager
    private var cachedToken: String?
    /// True while the active call is being managed by CallKit (both incoming and outgoing).
    private var callKitActive = false

    init(apiClient: APIClient, auth: AuthManager) {
        self.apiClient = apiClient
        self.auth = auth
        #if canImport(TwilioVoice)
        bindBridgeCallbacks()
        bindIncomingCallbacks()
        #endif
    }

    func clearError() {
        lastError = nil
    }

    struct PresenceBody: Encodable {
        let status: String
    }

    /// Report agent presence so the server routes inbound calls to this device. Inbound calls are
    /// only dialed to agents marked AVAILABLE, so this must be set once voice is ready.
    private func markPresence(_ status: String, surfaceErrors: Bool = false) {
        Task { [apiClient, weak self] in
            do {
                _ = try await apiClient.patch(
                    path: APIPath.voicePresence,
                    body: PresenceBody(status: status)
                ) as EmptyResponse
            } catch {
                guard surfaceErrors else { return }
                await MainActor.run {
                    self?.lastError = (error as? APIError)?.message
                        ?? "Voice presence update failed (\(status))"
                }
            }
        }
    }

    struct TokenResponse: Decodable {
        let token: String
        let identity: String
    }

    /// Fetch a Twilio access token for iOS (includes the Push Credential grant used for
    /// incoming-call registration).
    private func fetchToken() async throws -> String {
        let response: TokenResponse = try await apiClient.post(
            path: APIPath.voiceTokenPath(platform: "ios")
        )
        return response.token
    }

    func prepare() async {
        do {
            cachedToken = try await fetchToken()
            #if targetEnvironment(simulator)
            status = "Voice ready (simulator — use a real device to call)"
            #else
            status = "Voice ready"
            #endif
            lastError = nil
            #if canImport(TwilioVoice)
            startIncomingCalls()
            #endif
            // Advertise availability so inbound calls ring on this device.
            markPresence("AVAILABLE", surfaceErrors: true)
        } catch {
            lastError = (error as? APIError)?.message ?? error.localizedDescription
            status = "Voice unavailable"
        }
    }

    /// Register for incoming calls so the app rings on VoIP push (even when closed).
    func startIncomingCalls() {
        #if canImport(TwilioVoice) && canImport(PushKit) && canImport(CallKit)
        IncomingCallCoordinator.shared.start { [weak self] in
            guard let self else { return nil }
            return try? await self.fetchToken()
        }
        #endif
    }

    func stopIncomingCalls() {
        markPresence("OFFLINE")
        #if canImport(TwilioVoice) && canImport(PushKit) && canImport(CallKit)
        IncomingCallCoordinator.shared.stop()
        #endif
    }

    func call(phone: String, customerId: String? = nil) async {
        lastError = nil

        #if targetEnvironment(simulator)
        lastError = "Voice calls require a physical iPhone or iPad. The Simulator cannot place VoIP calls."
        #else
        let normalized = PhoneDialing.normalize(phone)
        guard !normalized.isEmpty else {
            lastError = "No phone number"
            return
        }

        guard await ensureMicrophoneAccess() else { return }

        guard auth.isAuthenticated else {
            lastError = "Sign in required"
            return
        }

        do {
            try await auth.ensureUserLoaded()
        } catch {
            lastError = (error as? APIError)?.message ?? "Unable to load account"
            return
        }

        guard let user = auth.user else {
            lastError = "Unable to load account"
            return
        }

        if cachedToken == nil {
            await prepare()
        }

        #if canImport(TwilioVoice)
        guard let token = cachedToken else {
            lastError = lastError ?? "Voice token unavailable"
            return
        }

        activePhone = normalized
        status = "Calling \(normalized)…"
        isInCall = true
        isIncoming = false
        markPresence("ON_CALL")

        var params: [String: String] = [
            "phoneNumber": normalized,
            "companyId": user.companyId,
            "userId": user.id,
        ]
        if let customerId, !customerId.isEmpty {
            params["customerId"] = customerId
        }

        #if canImport(PushKit) && canImport(CallKit)
        // Route through CallKit so the audio session activates and End/Mute stay in sync.
        callKitActive = true
        IncomingCallCoordinator.shared.startOutgoingCall(
            handleLabel: normalized,
            accessToken: token,
            params: params
        )
        #else
        callKitActive = false
        TwilioVoiceBridge.shared.connect(accessToken: token, params: params)
        #endif
        #else
        lastError = "Twilio Voice SDK not linked. Run xcodegen generate and add the TwilioVoice package."
        status = "SDK missing"
        #if canImport(UIKit)
        if let url = URL(string: "tel:\(normalized)") {
            await UIApplication.shared.open(url)
        }
        #endif
        #endif
        #endif
    }

    func hangUp() {
        #if canImport(TwilioVoice) && canImport(PushKit) && canImport(CallKit)
        if callKitActive {
            // CallKit drives the disconnect; state is reset in the onCallEnded callback.
            IncomingCallCoordinator.shared.endActiveCallFromUI()
            return
        }
        #endif
        #if canImport(TwilioVoice)
        TwilioVoiceBridge.shared.disconnect()
        #endif
        isInCall = false
        isMuted = false
        activePhone = nil
        lastError = nil
        status = cachedToken == nil ? "Ready" : "Voice ready"
        markPresence("AVAILABLE")
    }

    func toggleMute() {
        isMuted.toggle()
        #if canImport(TwilioVoice) && canImport(PushKit) && canImport(CallKit)
        if callKitActive {
            IncomingCallCoordinator.shared.setMuted(isMuted)
            return
        }
        #endif
        #if canImport(TwilioVoice)
        TwilioVoiceBridge.shared.setMuted(isMuted)
        #endif
    }

    #if canImport(AVFoundation)
    private func ensureMicrophoneAccess() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            lastError = "Microphone access is required for calls. Enable it in Settings → Storm CRM."
            return false
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted {
                lastError = "Microphone access is required for calls."
            }
            return granted
        @unknown default:
            return true
        }
    }
    #else
    private func ensureMicrophoneAccess() async -> Bool { true }
    #endif

    #if canImport(TwilioVoice)
    private func bindBridgeCallbacks() {
        let bridge = TwilioVoiceBridge.shared
        bridge.onStatusChange = { [weak self] message in
            self?.status = message
        }
        bridge.onConnected = { [weak self] in
            self?.isInCall = true
        }
        bridge.onDisconnected = { [weak self] in
            guard let self else { return }
            self.isInCall = false
            self.isMuted = false
            self.activePhone = nil
            self.status = self.cachedToken == nil ? "Ready" : "Voice ready"
            self.markPresence("AVAILABLE")
        }
        bridge.onError = { [weak self] message in
            self?.lastError = message
        }
    }

    private func bindIncomingCallbacks() {
        #if canImport(PushKit) && canImport(CallKit)
        let coordinator = IncomingCallCoordinator.shared
        coordinator.onCallAccepted = { [weak self] caller, incoming in
            Task { @MainActor in
                guard let self else { return }
                self.callKitActive = true
                self.isIncoming = incoming
                self.isInCall = true
                self.isMuted = false
                if let caller, !caller.isEmpty {
                    self.activePhone = caller
                } else if self.activePhone == nil {
                    self.activePhone = incoming ? "Incoming call" : "Active call"
                }
                self.status = "On call"
                self.markPresence("ON_CALL")
            }
        }
        coordinator.onCallEnded = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.callKitActive = false
                self.isIncoming = false
                self.isInCall = false
                self.isMuted = false
                self.activePhone = nil
                self.status = self.cachedToken == nil ? "Ready" : "Voice ready"
                self.markPresence("AVAILABLE")
            }
        }
        coordinator.onCallFailed = { [weak self] message in
            Task { @MainActor in
                self?.lastError = message
            }
        }
        coordinator.onVoIPRegistrationUpdated = { [weak self] succeeded, message in
            Task { @MainActor in
                guard let self else { return }
                if succeeded {
                    if !self.isInCall {
                        self.status = "Voice ready · listening"
                    }
                    if self.lastError?.contains("VoIP") == true || self.lastError?.contains("registration") == true {
                        self.lastError = nil
                    }
                } else if let message, !message.hasPrefix("Waiting for VoIP") {
                    self.lastError = "Incoming call registration failed: \(message)"
                }
            }
        }
        #endif
    }
    #endif
}

#if canImport(UIKit)
import UIKit
#endif
