import AVFoundation
import Foundation

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
    private var closed = true
    private var receiveTask: Task<Void, Never>?
    private var lastFrameAt: Date = .distantPast
    private var frameInFlight = false
    private let targetSampleRate: Double = 24_000
    private let frameMinInterval: TimeInterval = 2.5

    private let visualQuestionRegex = try? NSRegularExpression(
        pattern: #"\b(what|which|look|see|show|showing|this|that|valve|solenoid|controller|part|identify)\b"#,
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
        self.videoMode = videoMode
        self.visitId = visitId
        status = .connecting
        lastError = nil
        activeToolName = nil

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
            // Brief delay so the data channel / socket is ready before greeting.
            try? await Task.sleep(nanoseconds: 250_000_000)
            sendGreeting(video: videoMode)
        } catch {
            lastError = (error as? APIError)?.message ?? error.localizedDescription
            status = .error
            stopInternal(resetStatus: false)
        }
    }

    func captureFrameNow() async {
        await captureAndSendFrame(reason: "manual", force: true)
    }

    func stop() {
        stopInternal(resetStatus: true)
    }

    private func stopInternal(resetStatus: Bool) {
        closed = true
        receiveTask?.cancel()
        receiveTask = nil
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

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        activeToolName = nil
        if resetStatus {
            status = .idle
        }
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
                    if !Task.isCancelled, let self, !self.closed {
                        self.lastError = error.localizedDescription
                        self.status = .error
                    }
                    break
                }
            }
        }
    }

    private func sendJSON(_ payload: [String: Any]) {
        guard !closed,
              let ws = webSocket,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8)
        else { return }
        ws.send(.string(text)) { _ in }
    }

    private func sendGreeting(video: Bool) {
        sendJSON([
            "type": "response.create",
            "response": [
                "output_modalities": ["audio"],
                "instructions": video
                    ? "Greet the technician briefly. Mention you can see still frames from their camera when they ask about what they are showing. Then stop and listen."
                    : "Greet the technician briefly and offer to help with diagnostics, parts, or their performance. Then stop and listen.",
            ],
        ])
    }

    private func captureAndSendFrame(reason: String, force: Bool = false) async {
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
                        "text": "[Live camera frame (\(reason)). Use this image for what the technician is asking about.]",
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

        do {
            let result: FrameResponse = try await api.post(
                path: APIPath.stormAiRealtimeFrame,
                body: FrameBody(
                    conversationId: conversationId,
                    visitId: visitId,
                    dataUrl: dataUrl,
                    fileName: "storm-ai-frame-\(Int(Date().timeIntervalSince1970)).jpg"
                ),
                timeoutInterval: 90
            )
            onFrameSavedToJob?(result.savedToJob == true)
            if let resolved = result.visitId {
                self.visitId = resolved
            }
        } catch {
            // Frame still went to the model; job save can fail quietly.
        }
    }

    private func configureAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try session.setPreferredSampleRate(targetSampleRate)
        try session.setActive(true, options: [])

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let input = engine.inputNode
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
        guard !closed, let converter = micConverter else { return }
        let outFormat = converter.outputFormat
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

        var error: NSError?
        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
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
            status = .error

        case "input_audio_buffer.speech_started":
            status = .listening
            if videoMode {
                Task { await captureAndSendFrame(reason: "speech_started") }
            }

        case "response.created", "output_audio_buffer.started":
            status = .speaking

        case "response.output_audio.delta", "response.audio.delta":
            status = .speaking
            if let delta = json["delta"] as? String {
                playPCM16Base64(delta)
            }

        case "response.done", "response.cancelled", "output_audio_buffer.stopped":
            if status != .tool { status = .listening }

        case "conversation.item.input_audio_transcription.completed",
             "conversation.item.input_audio.transcription.completed":
            if let transcript = json["transcript"] as? String, !transcript.isEmpty {
                onTranscript?("user", transcript)
                if videoMode, looksLikeVisualQuestion(transcript) {
                    Task { await captureAndSendFrame(reason: "visual_question", force: true) }
                }
            }

        case "response.output_audio_transcript.done", "response.audio_transcript.done":
            if let transcript = json["transcript"] as? String, !transcript.isEmpty {
                onTranscript?("assistant", transcript)
            }

        case "response.function_call_arguments.delta":
            let callId = json["call_id"] as? String ?? ""
            let delta = json["delta"] as? String ?? ""
            pendingArgs[callId, default: ""] += delta

        case "response.function_call_arguments.done":
            let callId = json["call_id"] as? String ?? ""
            let name = json["name"] as? String ?? ""
            let argText = (json["arguments"] as? String) ?? pendingArgs[callId] ?? "{}"
            pendingArgs[callId] = nil
            await runTool(callId: callId, name: name, argText: argText)

        default:
            break
        }
    }

    private func looksLikeVisualQuestion(_ text: String) -> Bool {
        guard let regex = visualQuestionRegex else { return false }
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

    private func runTool(callId: String, name: String, argText: String) async {
        guard let conversationId else { return }
        status = .tool
        activeToolName = name

        var argsObject: [String: AnyCodableValue]?
        if let data = argText.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            argsObject = obj.mapValues { AnyCodableValue(from: $0) }
        }

        var output = #"{"ok":false,"error":"Tool request failed"}"#
        do {
            let resultData = try await api.postRawJSON(
                path: APIPath.stormAiRealtimeTools,
                body: StormAiRealtimeToolBody(
                    conversationId: conversationId,
                    callId: callId,
                    name: name,
                    arguments: argsObject
                ),
                timeoutInterval: 60
            )
            if let text = String(data: resultData, encoding: .utf8) {
                output = text
            }
        } catch {
            // keep default
        }

        sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": output,
            ],
        ])
        sendJSON([
            "type": "response.create",
            "response": [
                "output_modalities": ["audio"],
                "instructions":
                    "Continue speaking briefly with the technician using the tool result. Then stop and listen.",
            ],
        ])
        activeToolName = nil
        status = .speaking
    }
}
