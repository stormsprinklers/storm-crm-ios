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
final class IncomingCallCoordinator: NSObject {
    static let shared = IncomingCallCoordinator()

    private let pushRegistry = PKPushRegistry(queue: .main)
    private let callKitProvider: CXProvider
    private let callKitController = CXCallController()
    private let audioDevice = DefaultAudioDevice()

    private var voipDeviceToken: Data?
    private var accessTokenProvider: (() async -> String?)?
    private var isConfigured = false

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

    override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber, .generic]
        callKitProvider = CXProvider(configuration: configuration)
        super.init()
        callKitProvider.setDelegate(self, queue: nil)
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
        Task { await self.registerWithTwilio() }
    }

    /// Stop receiving incoming calls (e.g. on logout) and unregister the VoIP token from Twilio.
    func stop() {
        Task { await self.unregisterFromTwilio() }
        accessTokenProvider = nil
    }

    /// Refresh the Twilio registration with a new access token (call after token refresh).
    func refreshRegistration() {
        guard accessTokenProvider != nil else { return }
        Task { await self.registerWithTwilio() }
    }

    // MARK: - Twilio registration

    private func registerWithTwilio() async {
        guard let voipDeviceToken, let token = await accessTokenProvider?() else { return }
        TwilioVoiceSDK.register(accessToken: token, deviceToken: voipDeviceToken) { error in
            if let error {
                print("Twilio VoIP register failed:", error.localizedDescription)
            }
        }
    }

    private func unregisterFromTwilio() async {
        guard let voipDeviceToken, let token = await accessTokenProvider?() else { return }
        TwilioVoiceSDK.unregister(accessToken: token, deviceToken: voipDeviceToken) { error in
            if let error {
                print("Twilio VoIP unregister failed:", error.localizedDescription)
            }
        }
    }

    // MARK: - CallKit reporting

    private func reportIncomingCall(from: String, uuid: UUID) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: from)
        update.hasVideo = false
        update.supportsDTMF = true
        update.supportsHolding = false
        callKitProvider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if let error {
                print("CallKit reportNewIncomingCall failed:", error.localizedDescription)
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
        guard activeCall == nil, activeCallInvite == nil else { return }
        configure()

        let uuid = UUID()
        activeCallUUID = uuid
        isOutgoingCall = true
        outgoingHandleLabel = handleLabel
        pendingOutgoingConnect = (accessToken, params)

        let handle = CXHandle(type: .generic, value: handleLabel)
        let startAction = CXStartCallAction(call: uuid, handle: handle)
        startAction.isVideo = false
        callKitController.request(CXTransaction(action: startAction)) { [weak self] error in
            if let error {
                print("CallKit start call failed:", error.localizedDescription)
                self?.clearActiveCallState()
            }
        }
    }

    /// Whether an incoming call is currently ringing or connected.
    var hasActiveCall: Bool { activeCall != nil || activeCallInvite != nil }

    /// Mute toggle for the in-app call bar.
    func setMuted(_ muted: Bool) {
        activeCall?.isMuted = muted
    }

    private func clearActiveCallState() {
        guard activeCall != nil || activeCallInvite != nil || activeCallUUID != nil else { return }
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
        Task { await self.registerWithTwilio() }
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        Task { await self.unregisterFromTwilio() }
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
        reportIncomingCall(from: callInvite.from ?? "Incoming call", uuid: uuid)
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
        let label = isOutgoingCall ? outgoingHandleLabel : (call.from ?? activeCallInvite?.from)
        onCallAccepted?(label, !isOutgoingCall)
    }

    func callDidFailToConnect(call: Call, error: Error) {
        print("Incoming call failed to connect:", error.localizedDescription)
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
            action.fail()
            return
        }
        // Keep our audio device disabled until CallKit activates the session in didActivate.
        audioDevice.isEnabled = false
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
