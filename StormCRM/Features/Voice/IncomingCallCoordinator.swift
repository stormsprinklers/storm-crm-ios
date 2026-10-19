import Foundation

#if canImport(TwilioVoice) && canImport(PushKit) && canImport(CallKit)
import PushKit
import CallKit
import AVFoundation
import TwilioVoice

/// Owns the full incoming-call pipeline on iOS:
///  1. PushKit registers a VoIP token and hands it to Twilio so calls can wake the app.
///  2. When a call comes in, iOS delivers a VoIP push -> Twilio produces a `CallInvite`.
///  3. We immediately report the call to CallKit (required within the push run loop) so the
///     native incoming-call UI rings, including on the lock screen when the app is closed.
///  4. Answering/declining flows through CallKit and is applied to the Twilio call/invite.
///
/// Created on the main queue so all delegate callbacks land on the main thread.
/// Main-thread confined (PushKit queue is `.main`; CallKit delegate queue is nil/main).
final class IncomingCallCoordinator: NSObject, @unchecked Sendable {
    static let shared = IncomingCallCoordinator()

    private let pushRegistry = PKPushRegistry(queue: .main)
    private let callKitProvider: CXProvider
    private let callKitController = CXCallController()
    private let audioDevice = DefaultAudioDevice()

    private var voipDeviceToken: Data?
    private var accessTokenProvider: (() async -> String?)?
    private var isConfigured = false
    private var registeredAccessToken: String?
    private var registrationGeneration = 0
    private var registrationTask: Task<Void, Never>?

    private var incomingDisplayLabel: String?
    private var activeCallInvite: CallInvite?
    private var activeCall: Call?
    private var activeCallUUID: UUID?
    private var userInitiatedEnd = false

    // Outbound-call state (calls the tech places from the app, routed through CallKit so the
    // audio session activates the same way it does for incoming calls).
    private var isOutgoingCall = false
    private var outgoingHandleLabel: String?
    private var pendingOutgoingConnect: (accessToken: String, params: [String: String])?

    /// Called (on the main thread) when a call connects, with the remote label and whether it was
    /// an incoming call.
    var onCallAccepted: ((_ label: String?, _ isIncoming: Bool) -> Void)?
    /// Called (on the main thread) when the active call/invite ends for any reason.
    var onCallEnded: (() -> Void)?
    /// Called (on the main thread) when a call fails before or during connection.
    var onCallFailed: ((String) -> Void)?
    /// Called (on the main thread) after Twilio VoIP registration succeeds or fails.
    var onVoIPRegistrationUpdated: ((_ succeeded: Bool, _ message: String?) -> Void)?

    override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber, .generic]
        callKitProvider = CXProvider(configuration: configuration)
        super.init()
        callKitProvider.setDelegate(self, queue: nil)
        audioDevice.isEnabled = false
        // Route Twilio audio through the CallKit-managed session.
        TwilioVoiceSDK.audioDevice = audioDevice
    }

    // MARK: - Lifecycle

    /// Register the PushKit delegate as early as possible (app launch). This must happen before a
    /// VoIP push is delivered so we can report the incoming call to CallKit on a cold launch.
    /// Safe to call without an authenticated session.
    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        pushRegistry.delegate = self
        pushRegistry.desiredPushTypes = [.voIP]
    }

    /// Provide the Twilio access-token source and register this device for incoming calls.
    /// `accessTokenProvider` returns a fresh token (issued with a Push Credential grant).
    func start(accessTokenProvider: @escaping () async -> String?) {
        configure()
        self.accessTokenProvider = accessTokenProvider
        refreshRegistration()
    }

    /// Stop receiving incoming calls (e.g. on logout) and unregister the VoIP token from Twilio.
    func stop() async {
        let previousTokenProvider = accessTokenProvider
        registrationGeneration += 1
        accessTokenProvider = nil
        // Finish any old registration before a different company's identity can register.
        await registrationTask?.value
        registrationTask = nil
        // Unregister while the old account is still selected, using a fresh token
        // if the original registration token has already expired.
        let unregisterToken = await previousTokenProvider?() ?? registeredAccessToken
        if let token = unregisterToken, let deviceToken = voipDeviceToken {
            await unregisterFromTwilio(token: token, deviceToken: deviceToken)
        }
        registeredAccessToken = nil
    }

    /// Refresh the Twilio registration with a new access token (call after token refresh).
    func refreshRegistration() {
        guard accessTokenProvider != nil else { return }
        let previous = registrationTask
        registrationTask = Task {
            await previous?.value
            await self.registerWithTwilio()
        }
    }

    // MARK: - Twilio registration

    private func registerWithTwilio() async {
        let generation = registrationGeneration
        guard let voipDeviceToken else {
            await notifyVoIPRegistration(succeeded: false, message: "Waiting for VoIP push token from iOS")
            return
        }
        guard let token = await accessTokenProvider?() else {
            await notifyVoIPRegistration(succeeded: false, message: "Voice token unavailable for registration")
            return
        }
        guard generation == registrationGeneration else { return }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                TwilioVoiceSDK.register(accessToken: token, deviceToken: voipDeviceToken) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            registeredAccessToken = token
            guard generation == registrationGeneration else { return }
            await notifyVoIPRegistration(succeeded: true, message: nil)
        } catch {
            guard generation == registrationGeneration else { return }
            print("Twilio VoIP register failed:", error.localizedDescription)
            await notifyVoIPRegistration(succeeded: false, message: error.localizedDescription)
        }
    }

    private func unregisterFromTwilio(token: String, deviceToken: Data) async {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                TwilioVoiceSDK.unregister(accessToken: token, deviceToken: deviceToken) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            print("Twilio VoIP unregister failed:", error.localizedDescription)
        }
    }

    private func notifyVoIPRegistration(succeeded: Bool, message: String?) async {
        let callback = onVoIPRegistrationUpdated
        await MainActor.run {
            callback?(succeeded, message)
        }
    }

    // MARK: - CallKit reporting

    private func reportIncomingCall(from: String, displayName: String, uuid: UUID) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: from.hasPrefix("+") ? .phoneNumber : .generic, value: from)
        update.localizedCallerName = displayName
        update.hasVideo = false
        update.supportsDTMF = true
        update.supportsHolding = false
        let onFailed = onCallFailed
        callKitProvider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if let error {
                print("CallKit reportNewIncomingCall failed:", error.localizedDescription)
                onFailed?(error.localizedDescription)
                self?.clearActiveCallState()
            }
        }
    }

    private func endCallKitCall(_ uuid: UUID) {
        let endAction = CXEndCallAction(call: uuid)
        callKitController.request(CXTransaction(action: endAction)) { error in
            if let error {
                print("CallKit end request failed:", error.localizedDescription)
            }
        }
    }

    /// Called by the softphone UI ("End" button) so CallKit and Twilio stay in sync.
    func endActiveCallFromUI() {
        if let uuid = activeCallUUID {
            endCallKitCall(uuid)
        }
    }

    // MARK: - Outbound calls

    /// Place an outbound call through CallKit. Routing outbound calls through the same CallKit +
    /// audio-device pipeline as incoming calls is what activates the audio session (via
    /// `provider(_:didActivate:)`), so the Twilio call can reach the connected state instead of
    /// hanging in "Connecting…", and the End/Mute controls stay in sync.
    func startOutgoingCall(handleLabel: String, accessToken: String, params: [String: String]) {
        guard !hasActiveCall else {
            onCallFailed?("A call is already ringing or active")
            return
        }
        configure()

        let uuid = UUID()
        activeCallUUID = uuid
        isOutgoingCall = true
        outgoingHandleLabel = handleLabel
        pendingOutgoingConnect = (accessToken, params)

        let handle = CXHandle(type: .generic, value: handleLabel)
        let startAction = CXStartCallAction(call: uuid, handle: handle)
        startAction.isVideo = false
        let onFailed = onCallFailed
        callKitController.request(CXTransaction(action: startAction)) { [weak self] error in
            if let error {
                print("CallKit start call failed:", error.localizedDescription)
                onFailed?(error.localizedDescription)
                self?.clearActiveCallState()
            }
        }
    }

    /// Whether an incoming call is currently ringing or connected.
    var hasActiveCall: Bool { activeCall != nil || activeCallInvite != nil || activeCallUUID != nil }

    /// Mute toggle for the in-app call bar.
    func setMuted(_ muted: Bool) {
        activeCall?.isMuted = muted
    }

    private func clearActiveCallState() {
        guard activeCall != nil || activeCallInvite != nil || activeCallUUID != nil else { return }
        incomingDisplayLabel = nil
        activeCallInvite = nil
        activeCall = nil
        activeCallUUID = nil
        userInitiatedEnd = false
        isOutgoingCall = false
        outgoingHandleLabel = nil
        pendingOutgoingConnect = nil
        onCallEnded?()
    }
}

// MARK: - PushKit (VoIP)

extension IncomingCallCoordinator: PKPushRegistryDelegate {
    func pushRegistry(
        _ registry: PKPushRegistry,
        didUpdate pushCredentials: PKPushCredentials,
        for type: PKPushType
    ) {
        guard type == .voIP else { return }
        voipDeviceToken = pushCredentials.token
        refreshRegistration()
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        if let token = registeredAccessToken, let deviceToken = voipDeviceToken {
            Task { await self.unregisterFromTwilio(token: token, deviceToken: deviceToken) }
        }
        registeredAccessToken = nil
        voipDeviceToken = nil
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else {
            completion()
            return
        }
        // Twilio parses the push and calls back into our NotificationDelegate. We MUST report
        // an incoming call to CallKit before this returns, otherwise iOS terminates the app.
        TwilioVoiceSDK.handleNotification(payload.dictionaryPayload, delegate: self, delegateQueue: nil)
        completion()
    }
}

// MARK: - Twilio call-invite handling

extension IncomingCallCoordinator: NotificationDelegate {
    func callInviteReceived(callInvite: CallInvite) {
        // If we're already handling a call, reject the newcomer (single-line phone).
        if activeCallInvite != nil || activeCall != nil {
            callInvite.reject()
            return
        }
        let uuid = callInvite.uuid
        activeCallInvite = callInvite
        activeCallUUID = uuid
        let parameters = callInvite.customParameters ?? [:]
        let phone = parameters["callerPhone"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let caller = parameters["callerName"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let company = parameters["companyName"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let from = phone.flatMap { $0.isEmpty ? nil : $0 } ?? callInvite.from ?? "Unknown caller"
        let name = caller.flatMap { $0.isEmpty ? nil : $0 } ?? from
        let label = [name, company].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        incomingDisplayLabel = label
        reportIncomingCall(from: from, displayName: label, uuid: uuid)
    }

    func cancelledCallInviteReceived(cancelledCallInvite: CancelledCallInvite, error: Error) {
        guard let uuid = activeCallUUID, activeCallInvite?.callSid == cancelledCallInvite.callSid else {
            return
        }
        endCallKitCall(uuid)
    }
}

// MARK: - Twilio active-call delegate

extension IncomingCallCoordinator: CallDelegate {
    func callDidConnect(call: Call) {
        if isOutgoingCall, let uuid = activeCallUUID {
            callKitProvider.reportOutgoingCall(with: uuid, connectedAt: Date())
        }
        let label = isOutgoingCall ? outgoingHandleLabel : (incomingDisplayLabel ?? call.from ?? activeCallInvite?.from)
        onCallAccepted?(label, !isOutgoingCall)
    }

    func callDidFailToConnect(call: Call, error: Error) {
        print("Call failed to connect:", error.localizedDescription)
        onCallFailed?(error.localizedDescription)
        if let uuid = activeCallUUID {
            callKitProvider.reportCall(with: uuid, endedAt: Date(), reason: .failed)
        }
        clearActiveCallState()
    }

    func callDidDisconnect(call: Call, error: Error?) {
        // Only report an out-of-band end to CallKit when the call dropped remotely; a local
        // end already went through a fulfilled CXEndCallAction.
        if !userInitiatedEnd, let uuid = activeCallUUID {
            callKitProvider.reportCall(with: uuid, endedAt: Date(), reason: error == nil ? .remoteEnded : .failed)
        }
        clearActiveCallState()
    }
}

// MARK: - CallKit provider delegate

extension IncomingCallCoordinator: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        audioDevice.isEnabled = false
        activeCall?.disconnect()
        activeCallInvite?.reject()
        clearActiveCallState()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        guard let pending = pendingOutgoingConnect else {
            onCallFailed?("Outgoing call was not ready to connect")
            action.fail()
            return
        }
        // Keep our audio device disabled until CallKit activates the session in didActivate.
        audioDevice.isEnabled = false
        // Configure the play-and-record session before CallKit tries to activate it.
        audioDevice.block()
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())

        let options = ConnectOptions(accessToken: pending.accessToken) { builder in
            builder.params = pending.params
            builder.uuid = action.callUUID
        }
        activeCall = TwilioVoiceSDK.connect(options: options, delegate: self)
        pendingOutgoingConnect = nil
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let invite = activeCallInvite else {
            action.fail()
            return
        }
        // CallKit will activate the audio session next; keep our device disabled until then.
        audioDevice.isEnabled = false
        audioDevice.block()
        let options = AcceptOptions(callInvite: invite) { _ in }
        // Accept with `self` as the delegate so we can drive CallKit + the in-app UI.
        activeCall = invite.accept(options: options, delegate: self)
        activeCallInvite = nil
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        if let call = activeCall {
            // Let the disconnect delegate perform cleanup; don't double-report to CallKit.
            userInitiatedEnd = true
            call.disconnect()
        } else {
            activeCallInvite?.reject()
            clearActiveCallState()
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        activeCall?.isMuted = action.isMuted
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        audioDevice.isEnabled = true
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        audioDevice.isEnabled = false
    }
}
#endif
