import Foundation

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
            status = "Voice ready"
            lastError = nil
            #if canImport(TwilioVoice)
            startIncomingCalls()
            #endif
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
        #if canImport(TwilioVoice) && canImport(PushKit) && canImport(CallKit)
        IncomingCallCoordinator.shared.stop()
        #endif
    }

    func call(phone: String, customerId: String? = nil) async {
        lastError = nil
        let normalized = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            lastError = "No phone number"
            return
        }

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

        var params: [String: String] = [
            "phoneNumber": normalized,
            "companyId": user.companyId,
            "userId": user.id,
        ]
        if let customerId, !customerId.isEmpty {
            params["customerId"] = customerId
        }

        TwilioVoiceBridge.shared.connect(accessToken: token, params: params)
        #else
        lastError = "Twilio Voice SDK not linked. Run xcodegen generate and add the TwilioVoice package."
        status = "SDK missing"
        #if canImport(UIKit)
        if let url = URL(string: "tel:\(normalized)") {
            await UIApplication.shared.open(url)
        }
        #endif
        #endif
    }

    func hangUp() {
        #if canImport(TwilioVoice) && canImport(PushKit) && canImport(CallKit)
        if isIncoming {
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
    }

    func toggleMute() {
        isMuted.toggle()
        #if canImport(TwilioVoice) && canImport(PushKit) && canImport(CallKit)
        if isIncoming {
            IncomingCallCoordinator.shared.setMuted(isMuted)
            return
        }
        #endif
        #if canImport(TwilioVoice)
        TwilioVoiceBridge.shared.setMuted(isMuted)
        #endif
    }

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
            self?.isInCall = false
            self?.isMuted = false
            self?.activePhone = nil
            self?.status = self?.cachedToken == nil ? "Ready" : "Voice ready"
        }
        bridge.onError = { [weak self] message in
            self?.lastError = message
        }
    }

    private func bindIncomingCallbacks() {
        #if canImport(PushKit) && canImport(CallKit)
        let coordinator = IncomingCallCoordinator.shared
        coordinator.onCallAccepted = { [weak self] caller in
            Task { @MainActor in
                guard let self else { return }
                self.isIncoming = true
                self.isInCall = true
                self.isMuted = false
                self.activePhone = caller ?? "Incoming call"
                self.status = "On call"
            }
        }
        coordinator.onCallEnded = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isIncoming = false
                self.isInCall = false
                self.isMuted = false
                self.activePhone = nil
                self.status = self.cachedToken == nil ? "Ready" : "Voice ready"
            }
        }
        #endif
    }
    #endif
}

#if canImport(UIKit)
import UIKit
#endif
