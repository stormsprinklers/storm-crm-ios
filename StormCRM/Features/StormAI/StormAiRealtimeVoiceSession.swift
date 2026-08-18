import AVFoundation
import Foundation
import os

@MainActor
final class StormAiRealtimeVoiceSession: ObservableObject {
    enum Status: String {
        case idle
        case connecting
        case listening
        case speaking
        case tool
        case error
        case ended
    }

    @Published private(set) var status: Status = .idle {
        didSet { onStatusChange?(status) }
    }
    @Published private(set) var activeToolName: String?
    @Published var lastError: String?

    /// role ("user"|"assistant"), text
    var onTranscript: ((String, String) -> Void)?
    var onStatusChange: ((Status) -> Void)?
    var onFrameSavedToJob: ((Bool) -> Void)?
    var onVideoModeChange: ((Bool) -> Void)?
    var onPartsCard: ((StormAiPartsCardDTO) -> Void)?
    /// Live step log for the chat UI when the session goes silent.
    var onActivity: ((StormAiRealtimeActivity) -> Void)?

    private let api: APIClient
    private var conversationId: String?
    private var visitId: String?
    private var videoMode = false
    private var camera: StormAiCameraController?
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var micConverter: AVAudioConverter?
    private var pendingArgs: [String: String] = [:]
    private var pendingNames: [String: String] = [:]
    private var handledCallIds = Set<String>()
    private var closed = true
    private var receiveTask: Task<Void, Never>?
    private var searchFallbackTask: Task<Void, Never>?
    private var followUpTask: Task<Void, Never>?
    private var videoTurnTask: Task<Void, Never>?
    private var lastFrameAt: Date = .distantPast
    private var frameInFlight = false
    private var videoTurnPending = false
    private var awaitingFunctionOutput = false
    private var needsSpokenFollowUp = false
    private var inFlightTools = 0
    private var modelResponseActive = false
    private var followUpWaitStartedAt: Date?
    private var lastWaitActivityAt: Date = .distantPast
    private var toolPrefetch: [String: Task<String, Never>] = [:]
    private var lastUserTranscript = ""
    private var searchFallbackUsed = false
    /// Drop mic packets while the assistant is playing so speaker audio cannot be treated as a new user turn.
    private var suppressMicCapture = false
    private var resumeMicTask: Task<Void, Never>?
    private let targetSampleRate: Double = 24_000
    private let frameMinInterval: TimeInterval = 1.5
    private let toolTimeout: TimeInterval = 25
    private let searchFallbackDelayNs: UInt64 = 2_500_000_000
    private let videoTurnFlushNs: UInt64 = 1_800_000_000

    private let visualQuestionRegex = try? NSRegularExpression(
        pattern: #"\b(what|which|where|how|look|see|show|showing|this|that|here|valve|solenoid|controller|part|identify|tell me|can you|could you|manual)\b"#,
        options: [.caseInsensitive]
    )
    private let skipVideoFrameRegex = try? NSRegularExpression(
        pattern: #"^(ok|okay|yes|yeah|yep|no|nope|thanks|thank you|got it|alright|all right|continue|next|done|copy|uh-huh|mm-hmm)[\s.!?]*$"#,
        options: [.caseInsensitive]
    )
    private let searchingSpeechRegex = try? NSRegularExpression(
        pattern: #"\b(search|searching|look(ing)? up|check(ing)?|parts (list|library|info)|let me (find|check|look|search))\b"#,
        options: [.caseInsensitive]
    )

    init(api: APIClient) {
        self.api = api
    }

    var activeConversationId: String? { conversationId }
    var isVideoMode: Bool { videoMode }
    var cameraSession: AVCaptureSession? { camera?.session }

    var isActive: Bool {
        switch status {
        case .connecting, .listening, .speaking, .tool: return true
        default: return false
        }
    }

    func start(conversationId: String?, visitId: String? = nil, videoMode: Bool = false) async {
        stopInternal(resetStatus: false)
        closed = false
        handledCallIds.removeAll()
        awaitingFunctionOutput = false
        needsSpokenFollowUp = false
        inFlightTools = 0
        modelResponseActive = false
        followUpWaitStartedAt = nil
        clearFollowUpTimer()
        toolPrefetch.values.forEach { $0.cancel() }
        toolPrefetch.removeAll()
        searchFallbackUsed = false
        clearSearchFallback()
        self.videoMode = videoMode
        self.visitId = visitId
        status = .connecting
        lastError = nil
        activeToolName = nil
        onVideoModeChange?(videoMode)
        activity("Starting realtime session…")

        if let permissionError = await StormAiMediaPermissions.requestForRealtime(video: videoMode) {
            lastError = permissionError
            status = .error
            stopInternal(resetStatus: false)
            return
        }

        do {
            if videoMode {
                let cam = StormAiCameraController()
                camera = cam
                let started = await cam.start()
                if !started {
                    lastError = cam.lastError ?? "Could not start camera"
                    status = .error
                    stopInternal(resetStatus: false)
                    return
                }
            }

            let session: StormAiRealtimeSessionResponse = try await api.post(
                path: APIPath.stormAiRealtimeSession,
                body: StormAiRealtimeSessionBody(
                    conversationId: conversationId,
                    pageContext: StormAiPageContextBody(
                        pathname: videoMode ? "ios://storm-ai-video" : "ios://storm-ai-voice",
                        visitId: visitId
                    ),
                    videoMode: videoMode
                ),
                timeoutInterval: 60
            )
            self.conversationId = session.conversationId
            let model = session.model ?? "gpt-realtime"
            try await connectWebSocket(clientSecret: session.clientSecret, model: model)
            try configureAudio()
            status = .listening
            activity("Connected — listening", level: .ok)
            try? await Task.sleep(nanoseconds: 250_000_000)
            sendGreeting(video: videoMode)
        } catch {
            lastError = (error as? APIError)?.message ?? error.localizedDescription
            status = .error
            stopInternal(resetStatus: false)
        }
    }

    func enableVideo() async {
        guard isActive, !closed else {
            lastError = "Start voice first"
            return
        }
        if videoMode { return }

        if let permissionError = await StormAiMediaPermissions.requestForRealtime(video: true) {
            lastError = permissionError
            return
        }

        // voiceChat mode can blank the camera preview — switch to videoChat first.
        try? reconfigureAudioSession(forVideo: true)

        let cam = StormAiCameraController()
        let started = await cam.start()
        if !started {
            lastError = cam.lastError ?? "Could not start camera"
            return
        }
        camera = cam
        objectWillChange.send()
        videoMode = true
        onVideoModeChange?(true)
        sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": "[Video mode enabled. Send a camera frame only when I ask about what I am showing.]",
                    ],
                ],
            ],
        ])
        setAutoCreateResponse(false)
    }

    func disableVideo() {
        guard videoMode else { return }
        clearVideoTurn()
        setAutoCreateResponse(true)
        camera?.stop()
        camera = nil
        videoMode = false
        objectWillChange.send()
        onVideoModeChange?(false)
        try? reconfigureAudioSession(forVideo: false)
        sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": "[Video mode off. Continue this same voice conversation without new camera frames.]",
                    ],
                ],
            ],
        ])
    }

    func stop() {
        stopInternal(resetStatus: true)
    }

    private func stopInternal(resetStatus: Bool) {
        closed = true
        clearSearchFallback()
        clearFollowUpTimer()
        needsSpokenFollowUp = false
        followUpWaitStartedAt = nil
        inFlightTools = 0
        modelResponseActive = false
        clearVideoTurn()
        receiveTask?.cancel()
        receiveTask = nil
        resumeMicTask?.cancel()
        resumeMicTask = nil
        suppressMicCapture = false
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        engine?.inputNode.removeTap(onBus: 0)
        playerNode?.stop()
        engine?.stop()
        engine = nil
        playerNode = nil
        micConverter = nil
        camera?.stop()
        camera = nil
        videoMode = false
        onVideoModeChange?(false)

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        activeToolName = nil
        if resetStatus {
            status = .idle
        }
    }

    private func setAutoCreateResponse(_ enabled: Bool) {
        sendJSON([
            "type": "session.update",
            "session": [
                "audio": [
                    "input": [
                        "turn_detection": [
                            "type": "server_vad",
                            "threshold": 0.78,
                            "prefix_padding_ms": 400,
                            "silence_duration_ms": 900,
                            "interrupt_response": false,
                            "create_response": enabled,
                        ],
                    ],
                ],
            ],
        ])
    }

    private func clearVideoTurn() {
        videoTurnPending = false
        videoTurnTask?.cancel()
        videoTurnTask = nil
    }

    private func beginVideoTurn() {
        guard videoMode, !closed else { return }
        videoTurnPending = true
        videoTurnTask?.cancel()
        videoTurnTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.videoTurnFlushNs ?? 1_800_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.finishVideoTurn(withFrame: false)
        }
    }

    private func finishVideoTurn(withFrame: Bool) async {
        guard videoTurnPending, !closed else { return }
        clearVideoTurn()
        if withFrame {
            activity("Capturing camera frame for your question")
            await captureAndSendFrame(reason: "user_question", force: true)
        }
        sendJSON(["type": "response.create"])
    }

    private func clearSearchFallback() {
        searchFallbackTask?.cancel()
        searchFallbackTask = nil
    }

    private func clearFollowUpTimer() {
        followUpTask?.cancel()
        followUpTask = nil
    }

    private func activity(_ message: String, level: StormAiRealtimeActivity.Level = .info) {
        onActivity?(StormAiRealtimeActivity(level: level, message: message))
    }

    private func activityWait(_ message: String) {
        let now = Date()
        if now.timeIntervalSince(lastWaitActivityAt) < 1.2 { return }
        lastWaitActivityAt = now
        activity(message, level: .wait)
    }

    private func reconfigureAudioSession(forVideo: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: forVideo ? .videoChat : .voiceChat,
            options: [.defaultToSpeaker, AVAudioSession.CategoryOptions.allowBluetooth]
        )
        try session.setPreferredSampleRate(targetSampleRate)
        try session.setPreferredIOBufferDuration(0.02)
        if session.isInputGainSettable {
            try? session.setInputGain(0.75)
        }
        try session.setActive(true, options: [])
    }

    private func connectWebSocket(clientSecret: String, model: String) async throws {
        guard var components = URLComponents(string: "wss://api.openai.com/v1/realtime") else {
            throw APIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        guard let url = components.url else { throw APIError.invalidURL }

        let session = URLSession(configuration: .default)
        urlSession = session

        var request = URLRequest(url: url)
        request.setValue("Bearer \(clientSecret)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let task = session.webSocketTask(with: request)
        webSocket = task
        task.resume()

        for _ in 0..<40 {
            if closed { throw APIError.server("Voice session cancelled") }
            switch task.state {
            case .running:
                startReceiveLoop()
                return
            case .completed:
                throw APIError.server("Could not connect to Storm AI voice")
            default:
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        startReceiveLoop()
    }

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            while let self, !Task.isCancelled, !self.closed {
                guard let ws = self.webSocket else { break }
                do {
                    let message = try await ws.receive()
                    switch message {
                    case .string(let text):
                        await self.handleServerEvent(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await self.handleServerEvent(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled, !self.closed {
                        self.lastError = error.localizedDescription
                        self.status = .error
                    }
                    break
                }
            }
        }
    }

    @discardableResult
    private func sendJSON(_ payload: [String: Any]) -> Bool {
        guard !closed,
              let ws = webSocket,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8)
        else { return false }
        ws.send(.string(text)) { _ in }
        return true
    }

    private func sendGreeting(video: Bool) {
        sendJSON([
            "type": "response.create",
            "response": [
                "output_modalities": ["audio"],
                "instructions": video
                    ? "Greet the technician briefly. Mention you can see a camera still when they ask about what they are showing. Then stop and listen."
                    : "Greet the technician briefly and offer to help with diagnostics, parts, or their performance. Then stop and listen.",
            ],
        ])
    }

    private func captureAndSendFrame(reason: String, force: Bool = false) async {
        guard !awaitingFunctionOutput else { return }
        guard videoMode, !closed, let conversationId, let camera else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastFrameAt) < frameMinInterval { return }
        if frameInFlight { return }
        frameInFlight = true
        defer { frameInFlight = false }

        guard let jpeg = await camera.captureJPEG() else { return }
        lastFrameAt = now
        let dataUrl = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"

        sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_image",
                        "image_url": dataUrl,
                        "detail": "high",
                    ],
                    [
                        "type": "input_text",
                        "text": "[Camera frame for this question (\(reason)). Look at this image to answer.]",
                    ],
                ],
            ],
        ])

        struct FrameBody: Encodable {
            let conversationId: String
            let visitId: String?
            let dataUrl: String
            let fileName: String
        }
        struct FrameResponse: Decodable {
            let savedToJob: Bool?
            let visitId: String?
        }

        let capturedConversationId = conversationId
        let capturedVisitId = visitId
        Task {
            do {
                let result: FrameResponse = try await api.post(
                    path: APIPath.stormAiRealtimeFrame,
                    body: FrameBody(
                        conversationId: capturedConversationId,
                        visitId: capturedVisitId,
                        dataUrl: dataUrl,
                        fileName: "storm-ai-frame-\(Int(Date().timeIntervalSince1970)).jpg"
                    ),
                    timeoutInterval: 30
                )
                await MainActor.run {
                    onFrameSavedToJob?(result.savedToJob == true)
                    if let resolved = result.visitId {
                        self.visitId = resolved
                    }
                }
            } catch {
                // Frame still went to the model; job save can fail quietly.
            }
        }
    }

    private func configureAudio() throws {
        try reconfigureAudioSession(forVideo: videoMode)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(true)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw APIError.server("Microphone is not ready. Check mic permissions and try again.")
        }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw APIError.server("Could not create audio format")
        }

        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        micConverter = converter
        let playFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!
        engine.connect(player, to: engine.mainMixerNode, format: playFormat)

        input.installTap(onBus: 0, bufferSize: 2400, format: inputFormat) { [weak self] buffer, _ in
            Task { @MainActor in
                self?.appendMicAudio(buffer: buffer)
            }
        }

        try engine.start()
        player.play()
        self.engine = engine
        self.playerNode = player
    }

    private func appendMicAudio(buffer: AVAudioPCMBuffer) {
        guard !closed, !suppressMicCapture, let converter = micConverter else { return }
        let outFormat = converter.outputFormat
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

        var error: NSError?
        let consumed = OSAllocatedUnfairLock(initialState: false)
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            consumed.withLock { consumed in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }
        }
        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        guard error == nil, outBuffer.frameLength > 0, let channels = outBuffer.int16ChannelData else { return }

        let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: channels[0], count: byteCount)
        sendJSON([
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString(),
        ])
    }

    private func handleServerEvent(_ raw: String) async {
        guard !closed,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let type = json["type"] as? String ?? ""

        switch type {
        case "error":
            let err = json["error"] as? [String: Any]
            lastError = err?["message"] as? String ?? "Realtime error"
            activity("Server error: \(lastError ?? "Realtime error")", level: .error)
            status = .error

        case "input_audio_buffer.speech_started":
            status = .listening
            activity("Heard speech — listening")

        case "input_audio_buffer.speech_stopped":
            if videoMode { beginVideoTurn() }

        case "response.created", "output_audio_buffer.started":
            if type == "response.created" {
                modelResponseActive = true
                activity("Model started a response")
            }
            muteMicForPlayback()
            status = .speaking

        case "response.output_audio.delta", "response.audio.delta":
            muteMicForPlayback()
            status = .speaking
            if let delta = json["delta"] as? String {
                playPCM16Base64(delta)
            }

        case "response.cancelled", "output_audio_buffer.stopped":
            if type == "response.cancelled" {
                modelResponseActive = false
                activity("Model response cancelled", level: .wait)
            }
            if !awaitingFunctionOutput, !needsSpokenFollowUp {
                status = .listening
                unmuteMicAfterPlayback()
            }

        case "conversation.item.input_audio_transcription.completed",
             "conversation.item.input_audio.transcription.completed":
            if let transcript = json["transcript"] as? String, !transcript.isEmpty {
                lastUserTranscript = transcript
                onTranscript?("user", transcript)
                let clipped = transcript.count > 80 ? String(transcript.prefix(80)) + "…" : transcript
                activity("You: \(clipped)")
                if videoMode, videoTurnPending {
                    Task { await finishVideoTurn(withFrame: shouldSendCameraFrame(transcript)) }
                }
            }

        case "response.output_audio_transcript.done", "response.audio_transcript.done":
            if let transcript = json["transcript"] as? String, !transcript.isEmpty {
                onTranscript?("assistant", transcript)
                let clipped = transcript.count > 80 ? String(transcript.prefix(80)) + "…" : transcript
                activity("AI said: \(clipped)")
                maybeScheduleSearchFallback(transcript)
            }

        case "response.output_item.added":
            if let item = json["item"] as? [String: Any],
               (item["type"] as? String) == "function_call",
               let callId = item["call_id"] as? String,
               let name = item["name"] as? String {
                pendingNames[callId] = name
                status = .tool
                activeToolName = name
                clearSearchFallback()
                activity("Tool call started: \(name)")
            }

        case "response.function_call_arguments.delta":
            let callId = json["call_id"] as? String ?? ""
            let delta = json["delta"] as? String ?? ""
            if !callId.isEmpty {
                pendingArgs[callId, default: ""] += delta
                if let name = json["name"] as? String, !name.isEmpty {
                    pendingNames[callId] = name
                }
            }

        case "response.function_call_arguments.done":
            let callId = json["call_id"] as? String ?? ""
            let name = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? pendingNames[callId]
                ?? ""
            let argText = (json["arguments"] as? String) ?? pendingArgs[callId] ?? "{}"
            pendingArgs[callId] = nil
            if !name.isEmpty { pendingNames[callId] = name }
            if !callId.isEmpty, !name.isEmpty {
                clearSearchFallback()
                await completeFunctionCall(callId: callId, name: name, argText: argText)
            }

        case "response.output_item.done":
            if let item = json["item"] as? [String: Any],
               (item["type"] as? String) == "function_call",
               let callId = item["call_id"] as? String,
               let name = item["name"] as? String {
                clearSearchFallback()
                let argText = (item["arguments"] as? String) ?? pendingArgs[callId] ?? "{}"
                await completeFunctionCall(callId: callId, name: name, argText: argText)
            }

        case "response.done":
            modelResponseActive = false
            activity("Model turn finished")
            if let response = json["response"] as? [String: Any],
               let outputs = response["output"] as? [[String: Any]] {
                for item in outputs where (item["type"] as? String) == "function_call" {
                    if let callId = item["call_id"] as? String,
                       let name = item["name"] as? String {
                        clearSearchFallback()
                        let argText = (item["arguments"] as? String) ?? "{}"
                        await completeFunctionCall(callId: callId, name: name, argText: argText)
                    }
                }
            }

            scheduleSpokenFollowUp(delayNs: 80_000_000)
            if !awaitingFunctionOutput, !needsSpokenFollowUp, inFlightTools == 0 {
                status = .listening
                unmuteMicAfterPlayback()
            }

        default:
            break
        }
    }

    private func shouldSendCameraFrame(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 3 { return false }
        if let skip = skipVideoFrameRegex {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            if skip.firstMatch(in: trimmed, options: [], range: range) != nil { return false }
        }
        if trimmed.contains("?") { return true }
        if let regex = visualQuestionRegex {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            if regex.firstMatch(in: trimmed, options: [], range: range) != nil { return true }
        }
        return trimmed.split(whereSeparator: { $0.isWhitespace }).count >= 3
    }

    private func looksLikeSearchingSpeech(_ text: String) -> Bool {
        guard let regex = searchingSpeechRegex else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private func playPCM16Base64(_ b64: String) {
        guard let data = Data(base64Encoded: b64),
              let player = playerNode
        else { return }

        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: targetSampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return }

        buffer.frameLength = frameCount
        data.withUnsafeBytes { raw in
            guard let src = raw.bindMemory(to: Int16.self).baseAddress,
                  let dst = buffer.floatChannelData?[0]
            else { return }
            for i in 0..<Int(frameCount) {
                dst[i] = Float(src[i]) / Float(Int16.max)
            }
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    private func muteMicForPlayback() {
        resumeMicTask?.cancel()
        resumeMicTask = nil
        suppressMicCapture = true
        sendJSON(["type": "input_audio_buffer.clear"])
    }

    private func unmuteMicAfterPlayback() {
        resumeMicTask?.cancel()
        resumeMicTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, !Task.isCancelled, !self.closed else { return }
            self.suppressMicCapture = false
        }
    }

    private func completeFunctionCall(callId: String, name: String, argText: String) async {
        guard !callId.isEmpty, !name.isEmpty else { return }
        if handledCallIds.contains(callId) {
            activity("Skipping duplicate tool call \(name)", level: .wait)
            return
        }
        handledCallIds.insert(callId)

        awaitingFunctionOutput = true
        inFlightTools += 1
        status = .tool
        activeToolName = name
        activity("Running \(name)…", level: .wait)

        if toolPrefetch[callId] == nil {
            toolPrefetch[callId] = Task {
                await self.fetchToolResult(callId: callId, name: name, argText: argText)
            }
        }
        let started = Date()
        let output = await toolPrefetch[callId]?.value
            ?? #"{"ok":false,"error":"Tool request failed"}"#
        toolPrefetch[callId] = nil

        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        let ok: Bool = {
            guard let data = output.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            if let flag = root["ok"] as? Bool { return flag }
            return root["error"] == nil
        }()
        activity(
            ok ? "\(name) returned in \(elapsedMs)ms" : "\(name) failed (\(elapsedMs)ms)",
            level: ok ? .ok : .error
        )

        publishPartsCard(from: output)
        if output.contains("\"chatCard\"") {
            activity("Parts card sent to chat", level: .ok)
        }
        let forModel = stripChatCard(from: output)
        activity("Sending \(name) result to model…")

        let sent = sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": forModel,
            ],
        ])
        inFlightTools = max(0, inFlightTools - 1)
        if !sent {
            lastError = "Lost connection while looking something up — tap mic to reconnect."
            activity("Lost connection while sending tool result", level: .error)
            status = .error
            awaitingFunctionOutput = false
            return
        }

        if inFlightTools == 0 {
            awaitingFunctionOutput = false
            needsSpokenFollowUp = true
            activity("Tool result delivered — waiting to speak answer", level: .wait)
            scheduleSpokenFollowUp(delayNs: 250_000_000)
        }
    }

    private func scheduleSpokenFollowUp(delayNs: UInt64) {
        clearFollowUpTimer()
        if followUpWaitStartedAt == nil, needsSpokenFollowUp {
            followUpWaitStartedAt = Date()
        }
        followUpTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNs)
            guard let self, !Task.isCancelled else { return }
            if self.closed { return }
            if self.inFlightTools > 0 || self.awaitingFunctionOutput {
                self.activityWait("Waiting for \(max(self.inFlightTools, 1)) tool(s) to finish…")
                self.scheduleSpokenFollowUp(delayNs: 300_000_000)
                return
            }
            if self.modelResponseActive {
                let waited = Date().timeIntervalSince(self.followUpWaitStartedAt ?? Date())
                if waited > 4 {
                    self.activity("Model turn stuck open >4s — forcing spoken answer", level: .wait)
                    self.modelResponseActive = false
                } else {
                    self.activityWait("Waiting for current model turn to end…")
                    self.scheduleSpokenFollowUp(delayNs: 300_000_000)
                    return
                }
            }
            guard self.needsSpokenFollowUp else { return }
            self.needsSpokenFollowUp = false
            self.followUpWaitStartedAt = nil
            self.requestSpokenToolFollowUp()
        }
    }

    private func publishPartsCard(from resultJson: String) {
        guard let data = resultJson.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cardObj = root["chatCard"] as? [String: Any],
              let cardData = try? JSONSerialization.data(withJSONObject: cardObj),
              let card = try? JSONDecoder().decode(StormAiPartsCardDTO.self, from: cardData)
        else { return }
        onPartsCard?(card)
    }

    private func stripChatCard(from resultJson: String) -> String {
        guard let data = resultJson.data(using: .utf8),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return resultJson }
        root.removeValue(forKey: "chatCard")
        guard let out = try? JSONSerialization.data(withJSONObject: root),
              let text = String(data: out, encoding: .utf8)
        else { return resultJson }
        return text
    }

    private func requestSpokenToolFollowUp() {
        activity("Asking model to speak the tool answer…")
        let sent = sendJSON(["type": "response.create"])
        if !sent {
            lastError = "Lost connection while looking something up — tap mic to reconnect."
            activity("Could not request spoken answer — connection lost", level: .error)
            status = .error
            return
        }
        modelResponseActive = true
        activeToolName = nil
        muteMicForPlayback()
        status = .speaking
    }

    private func fetchToolResult(callId: String, name: String, argText: String) async -> String {
        guard let conversationId else {
            return #"{"ok":false,"error":"Tool request failed"}"#
        }

        var argsObject: [String: StormAiJSONValue]?
        if let data = argText.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            argsObject = obj.mapValues { StormAiJSONValue(from: $0) }
        }

        do {
            let resultData = try await api.postRawJSON(
                path: APIPath.stormAiRealtimeTools,
                body: StormAiRealtimeToolBody(
                    conversationId: conversationId,
                    callId: callId,
                    name: name,
                    arguments: argsObject
                ),
                timeoutInterval: toolTimeout
            )
            if let text = String(data: resultData, encoding: .utf8) {
                return text
            }
        } catch {
            let message = (error as? APIError)?.message ?? error.localizedDescription
            let timedOut = message.localizedCaseInsensitiveContains("timed out")
                || message.localizedCaseInsensitiveContains("timeout")
                || message.localizedCaseInsensitiveContains("cancelled")
            return timedOut
                ? #"{"ok":false,"error":"Tool timed out — tell the tech briefly and ask them to continue."}"#
                : #"{"ok":false,"error":"Tool request failed"}"#
        }
        return #"{"ok":false,"error":"Tool request failed"}"#
    }

    private func maybeScheduleSearchFallback(_ assistantTranscript: String) {
        guard looksLikeSearchingSpeech(assistantTranscript) else { return }
        guard !searchFallbackUsed, !awaitingFunctionOutput else { return }
        guard !needsSpokenFollowUp, inFlightTools == 0 else { return }

        activity("AI said it would search — starting fallback timer (2.5s)", level: .wait)
        clearSearchFallback()
        searchFallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.searchFallbackDelayNs ?? 2_500_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.runSearchFallback()
        }
    }

    private func runSearchFallback() async {
        guard !closed, !searchFallbackUsed, !awaitingFunctionOutput else { return }
        guard !needsSpokenFollowUp, inFlightTools == 0, conversationId != nil else { return }

        searchFallbackUsed = true
        status = .tool
        activeToolName = "search_parts_info"
        activity("No tool call yet — running client parts search fallback", level: .wait)

        let query = lastUserTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "identify irrigation part from camera description valve solenoid controller"
            : lastUserTranscript

        let argText: String
        if let data = try? JSONSerialization.data(withJSONObject: ["query": query]),
           let encoded = String(data: data, encoding: .utf8) {
            argText = encoded
        } else {
            argText = #"{"query":"identify irrigation part"}"#
        }

        let result = await fetchToolResult(
            callId: "fallback-\(Int(Date().timeIntervalSince1970))",
            name: "search_parts_info",
            argText: argText
        )

        publishPartsCard(from: result)
        activity("Fallback search finished — forcing spoken answer", level: .ok)

        let spoken = formatPartsFallbackSpeech(resultJson: result)
        sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": "[Parts library search already completed. Results JSON follows. Speak the answer to the technician now using only these results. Do not say you are still searching or waiting. Photos and manuals are already shown in chat.]\n\(stripChatCard(from: result))",
                    ],
                ],
            ],
        ])
        sendJSON([
            "type": "response.create",
            "response": [
                "instructions": spoken
                    ?? "Tell the technician the parts library search finished and summarize the tool JSON that was just added. Do not say you are still waiting.",
            ],
        ])
        modelResponseActive = true
        activeToolName = nil
        muteMicForPlayback()
        status = .speaking

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            self?.searchFallbackUsed = false
        }
    }

    private func formatPartsFallbackSpeech(resultJson: String) -> String? {
        guard let data = resultJson.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let payload = (root["data"] as? [String: Any]) ?? root
        let parts = payload["parts"] as? [[String: Any]] ?? []
        guard let top = parts.first else {
            return "Speak this: I checked the parts library and did not find a match for what you are showing. Then stop and listen."
        }
        let name = top["name"] as? String ?? "a matching part"
        let manufacturer = (top["manufacturer"] as? String).flatMap { $0.isEmpty ? nil : " by \($0)" } ?? ""
        let partNumber = (top["partNumber"] as? String).flatMap { $0.isEmpty ? nil : ", part number \($0)" } ?? ""
        return "Speak this to the technician now, then stop and listen: From the parts library, this looks like \(name)\(manufacturer)\(partNumber)."
    }
}
