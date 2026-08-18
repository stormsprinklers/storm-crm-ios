import PhotosUI
import SwiftUI

private struct StormAiPendingPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    let dataUrl: String
    let fileName: String
    let mimeType: String
}

struct StormAiChatView: View {
    @EnvironmentObject private var env: AppEnvironment

    var visitId: String? = nil

    @State private var conversationId: String?
    @State private var messages: [StormAiMessageDTO] = []
    @State private var draft = ""
    @State private var pendingPhotos: [StormAiPendingPhoto] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var isSending = false
    @State private var isLoading = true
    @State private var error: String?
    @State private var warning: String?
    @State private var voiceSession: StormAiRealtimeVoiceSession?
    @State private var voiceStatus: StormAiRealtimeVoiceSession.Status = .idle
    @State private var voiceToolName: String?
    @State private var voiceActivity: [StormAiRealtimeActivity] = []
    @State private var videoModeActive = false
    @State private var frameSavedToast: String?
    /// Set only when Storm AI is opened from a visit. Never inferred from the active job.
    @State private var linkedVisitTitle: String?
    @State private var pastConversations: [StormAiConversationDTO] = []
    @State private var historyExpanded = false

    private let maxPhotos = 4

    private var voiceActive: Bool {
        switch voiceStatus {
        case .connecting, .listening, .speaking, .tool: return true
        default: return false
        }
    }

    private var canSend: Bool {
        !isSending &&
            (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingPhotos.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !pastConversations.isEmpty {
                DisclosureGroup("Past chats", isExpanded: $historyExpanded) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(pastConversations) { thread in
                            Button {
                                Task { await openConversation(thread.id) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(thread.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                         ? thread.title!
                                         : "Untitled chat")
                                        .font(.subheadline)
                                        .foregroundStyle(thread.id == conversationId ? StormTheme.navy : .primary)
                                        .lineLimit(1)
                                    if let updated = thread.updatedAt, !updated.isEmpty {
                                        Text(updated)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemFill))
            }

            if videoModeActive, let session = voiceSession?.cameraSession {
                StormAiCameraPreview(session: session)
                    .id(ObjectIdentifier(session))
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal)
                    .padding(.top, 8)
                Text("Live preview — a still is sent when you ask about what you see")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if isLoading && messages.isEmpty {
                            ProgressView("Loading…")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 24)
                        } else if messages.isEmpty && !isSending && !voiceActive {
                            Text(
                                visitId == nil
                                    ? "Ask about customers, attach a part photo, or use mic/video."
                                    : "Mic for voice, video to add the camera. A still is sent when you ask about what you see, and saved to this job."
                            )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }

                        if visitId != nil {
                            Label(linkedVisitTitle ?? "This visit", systemImage: "wrench.and.screwdriver")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(messages) { message in
                            stormBubble(message)
                                .id(message.id)
                        }

                        if isSending {
                            Text("Thinking…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .id("thinking")
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: isSending) { _, sending in
                    if sending { scrollToBottom(proxy) }
                }
            }

            if voiceActive {
                voiceLiveSteps
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
            if let warning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
            if let voiceError = voiceSession?.lastError, voiceActive || voiceStatus == .error {
                Text(voiceError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            if let frameSavedToast {
                Text(frameSavedToast)
                    .font(.caption)
                    .foregroundStyle(StormTheme.success)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            if !pendingPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingPhotos) { photo in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: photo.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Button {
                                    pendingPhotos.removeAll { $0.id == photo.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: max(1, maxPhotos - pendingPhotos.count),
                    matching: .images
                ) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3)
                        .foregroundStyle(StormTheme.sky)
                }
                .disabled(isSending || pendingPhotos.count >= maxPhotos)

                Button {
                    showCamera = true
                } label: {
                    Image(systemName: "camera")
                        .font(.title3)
                        .foregroundStyle(StormTheme.sky)
                }
                .disabled(isSending || pendingPhotos.count >= maxPhotos)

                Button {
                    Task { await toggleMic() }
                } label: {
                    Image(systemName: voiceActive ? "mic.circle.fill" : "mic.circle")
                        .font(.title2)
                        .foregroundStyle(voiceActive ? StormTheme.coral : StormTheme.sky)
                }
                .disabled(isSending)

                Button {
                    Task { await toggleCamera() }
                } label: {
                    Image(systemName: voiceActive && videoModeActive ? "video.circle.fill" : "video.circle")
                        .font(.title2)
                        .foregroundStyle(voiceActive && videoModeActive ? StormTheme.coral : StormTheme.sky)
                }
                .disabled(isSending)

                TextField("Ask Storm AI…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSending)

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(StormTheme.sky)
                    }
                }
                .disabled(!canSend)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .background(StormTheme.page.ignoresSafeArea())
        .navigationTitle("Storm AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New chat") {
                    beginNewThread()
                }
                .disabled(isSending)
            }
        }
        .task {
            beginNewThread()
            if visitId != nil {
                linkedVisitTitle = "This visit"
            }
            await loadHistory()
        }
        .onDisappear {
            voiceSession?.stop()
            voiceStatus = .idle
            voiceToolName = nil
            videoModeActive = false
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await importPickerItems(items)
                pickerItems = []
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraImagePicker { image in
                appendPending(image: image)
            }
            .ignoresSafeArea()
        }
    }

    private var voiceLiveSteps: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(voiceStatusLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(StormTheme.navy)
            if voiceActivity.isEmpty {
                Text("Live steps will appear here while voice is active.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if let latest = voiceActivity.last {
                Text(latest.message)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(activityColor(latest.level))
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private func activityColor(_ level: StormAiRealtimeActivity.Level) -> Color {
        switch level {
        case .info: return .secondary
        case .wait: return .orange
        case .ok: return StormTheme.success
        case .error: return .red
        }
    }

    private var voiceStatusLabel: String {
        switch voiceStatus {
        case .connecting: return "Connecting voice…"
        case .tool: return "Looking up \(voiceToolName ?? "CRM data")…"
        case .speaking: return "Storm AI speaking…"
        case .listening:
            return videoModeActive
                ? "Listening — point the camera and ask about what you see"
                : "Listening — speak anytime"
        case .error: return "Voice error"
        default: return "Voice…"
        }
    }

    private func ensureVoiceSession() -> StormAiRealtimeVoiceSession {
        if let existing = voiceSession {
            return existing
        }
        let session = StormAiRealtimeVoiceSession(api: env.apiClient)
        session.onTranscript = { role, text in
            if messages.last?.role == role, messages.last?.content == text { return }
            messages.append(
                StormAiMessageDTO(
                    id: "voice-\(UUID().uuidString)",
                    role: role,
                    content: text,
                    createdAt: ISO8601DateFormatter().string(from: Date()),
                    attachments: nil
                )
            )
        }
        session.onStatusChange = { status in
            voiceStatus = status
            voiceToolName = session.activeToolName
        }
        session.onVideoModeChange = { enabled in
            videoModeActive = enabled
        }
        session.onPartsCard = { card in
            if messages.contains(where: { $0.partsCard?.partId == card.partId }) { return }
            messages.append(
                StormAiMessageDTO(
                    id: "parts-\(card.partId)-\(UUID().uuidString)",
                    role: "assistant",
                    content: card.name,
                    createdAt: ISO8601DateFormatter().string(from: Date()),
                    attachments: nil,
                    partsCard: card
                )
            )
        }
        session.onActivity = { entry in
            voiceActivity.append(entry)
            if voiceActivity.count > 30 {
                voiceActivity.removeFirst(voiceActivity.count - 30)
            }
        }
        session.onFrameSavedToJob = { saved in
            if saved {
                frameSavedToast = "Frame saved to job attachments"
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if frameSavedToast == "Frame saved to job attachments" {
                        frameSavedToast = nil
                    }
                }
            }
        }
        voiceSession = session
        return session
    }

    private func toggleMic() async {
        let session = ensureVoiceSession()
        if voiceActive {
            session.stop()
            voiceStatus = .idle
            voiceToolName = nil
            videoModeActive = false
            voiceActivity = []
            return
        }
        error = nil
        warning = nil
        videoModeActive = false
        voiceActivity = []
        await session.start(
            conversationId: conversationId,
            visitId: visitId,
            videoMode: false
        )
        voiceStatus = session.status
        voiceToolName = session.activeToolName
        videoModeActive = session.isVideoMode
        if let id = session.activeConversationId {
            conversationId = id
        }
        if let voiceError = session.lastError {
            error = voiceError
            videoModeActive = false
        }
    }

    private func toggleCamera() async {
        let session = ensureVoiceSession()
        error = nil
        warning = nil

        // Already in a live session: toggle camera without dropping conversation.
        if session.isActive {
            if session.isVideoMode {
                session.disableVideo()
                videoModeActive = false
            } else {
                await session.enableVideo()
                videoModeActive = session.isVideoMode
                if let voiceError = session.lastError {
                    error = voiceError
                }
            }
            voiceStatus = session.status
            return
        }

        // Start a new realtime session with video (same chat conversation id).
        videoModeActive = true
        voiceActivity = []
        await session.start(
            conversationId: conversationId,
            visitId: visitId,
            videoMode: true
        )
        voiceStatus = session.status
        voiceToolName = session.activeToolName
        videoModeActive = session.isVideoMode
        if let id = session.activeConversationId {
            conversationId = id
        }
        if let voiceError = session.lastError {
            error = voiceError
            videoModeActive = false
        }
    }

    private func beginNewThread() {
        voiceSession?.stop()
        voiceStatus = .idle
        voiceToolName = nil
        videoModeActive = false
        voiceActivity = []
        conversationId = nil
        messages = []
        draft = ""
        pendingPhotos = []
        error = nil
        warning = nil
        historyExpanded = false
        isLoading = false
    }

    private func loadHistory() async {
        do {
            let list: StormAiConversationListResponse = try await env.apiClient.get(
                path: APIPath.stormAiConversations
            )
            pastConversations = list.conversations
        } catch {
            // History is optional — a new thread still works.
        }
    }

    private func openConversation(_ id: String) async {
        voiceSession?.stop()
        voiceStatus = .idle
        voiceToolName = nil
        videoModeActive = false
        voiceActivity = []
        error = nil
        warning = nil
        historyExpanded = false
        isLoading = true
        defer { isLoading = false }
        do {
            let detail: StormAiConversationDetailResponse = try await env.apiClient.get(
                path: APIPath.stormAiConversation(id)
            )
            conversationId = detail.conversation.id
            messages = detail.conversation.messages
            draft = ""
            pendingPhotos = []
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func stormBubble(_ message: StormAiMessageDTO) -> some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                if let attachments = message.attachments, !attachments.isEmpty {
                    ForEach(attachments, id: \.url) { attachment in
                        Group {
                            if attachment.url.hasPrefix("data:"),
                               let uiImage = uiImage(fromDataUrl: attachment.url) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                AuthenticatedBlobImage(urlString: attachment.url, contentMode: .fill)
                            }
                        }
                        .frame(width: 160, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                if let card = message.partsCard {
                    partsCardView(card)
                } else {
                    Group {
                        if let attributed = try? AttributedString(markdown: message.content) {
                            Text(attributed)
                        } else {
                            Text(message.content)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(StormTheme.navy)
                    .padding(12)
                    .background(message.isUser ? StormTheme.sky.opacity(0.18) : Color(.secondarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            if !message.isUser { Spacer(minLength: 40) }
        }
    }

    private func partsCardView(_ card: StormAiPartsCardDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(StormTheme.navy)

            if card.visuallyConfirmed == true {
                Text("Photo match")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.85))
                    .clipShape(Capsule())
            }

            if !card.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(card.photos, id: \.url) { photo in
                            ZStack(alignment: .topLeading) {
                                AuthenticatedBlobImage(urlString: photo.url, contentMode: .fill)
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(
                                                photo.id != nil && photo.id == card.confirmedPhotoId
                                                    ? Color.green
                                                    : Color.clear,
                                                lineWidth: 3
                                            )
                                    )
                                if photo.id != nil, photo.id == card.confirmedPhotoId {
                                    Text("Match")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.green.opacity(0.9))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .padding(6)
                                }
                            }
                        }
                    }
                }
            }

            let meta = [card.manufacturer, card.partNumber, card.section]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            let summary = (card.summary?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? ([card.name, meta.isEmpty ? nil : meta].compactMap { $0 }.joined(separator: ". "))
            if !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(StormTheme.navy)
            }
            if let manualUrl = card.manualUrl, let url = URL(string: manualUrl) {
                Link(card.manualKind == "pdf" ? "Open manual (PDF)" : "Open manual", destination: url)
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if isSending {
            proxy.scrollTo("thinking", anchor: .bottom)
        } else if let last = messages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func importPickerItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard pendingPhotos.count < maxPhotos else { break }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)
                else { continue }
                appendPending(image: image)
            } catch {
                self.error = (error as? APIError)?.message ?? error.localizedDescription
            }
        }
    }

    private func appendPending(image: UIImage) {
        guard pendingPhotos.count < maxPhotos else {
            error = "You can attach up to \(maxPhotos) photos"
            return
        }
        guard let jpeg = image.stormAiResizedJPEG(maxEdge: 1280, quality: 0.82),
              let dataUrl = dataUrl(from: jpeg, mimeType: "image/jpeg")
        else {
            error = "Could not read photo"
            return
        }
        let fileName = "photo-\(Int(Date().timeIntervalSince1970)).jpg"
        pendingPhotos.append(
            StormAiPendingPhoto(
                image: image,
                dataUrl: dataUrl,
                fileName: fileName,
                mimeType: "image/jpeg"
            )
        )
    }

    private func dataUrl(from data: Data, mimeType: String) -> String? {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private func uiImage(fromDataUrl dataUrl: String) -> UIImage? {
        guard let comma = dataUrl.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataUrl[dataUrl.index(after: comma)...]))
        else { return nil }
        return UIImage(data: data)
    }

    private func send() async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let photos = pendingPhotos
        guard (!content.isEmpty || !photos.isEmpty), !isSending else { return }
        // Keep one conversation: end live voice/video first, then continue in text.
        if voiceActive {
            voiceSession?.stop()
            voiceStatus = .idle
            voiceToolName = nil
            videoModeActive = false
        }
        error = nil
        warning = nil
        draft = ""
        pendingPhotos = []
        isSending = true
        defer { isSending = false }

        do {
            var id = conversationId
            if id == nil {
                let created: StormAiConversationCreatedResponse = try await env.apiClient.post(
                    path: APIPath.stormAiConversations
                )
                id = created.conversation.id
                conversationId = id
            }
            guard let conversationId = id else { return }

            let localAttachments = photos.map {
                StormAiAttachmentDTO(
                    fileName: $0.fileName,
                    mimeType: $0.mimeType,
                    kind: "image",
                    url: $0.dataUrl
                )
            }
            messages.append(
                StormAiMessageDTO(
                    id: "local-\(UUID().uuidString)",
                    role: "user",
                    content: content.isEmpty ? "What part is this?" : content,
                    createdAt: ISO8601DateFormatter().string(from: Date()),
                    attachments: localAttachments.isEmpty ? nil : localAttachments
                )
            )

            let imageBodies = photos.map {
                StormAiSendImageBody(
                    dataUrl: $0.dataUrl,
                    fileName: $0.fileName,
                    mimeType: $0.mimeType
                )
            }
            let body = StormAiSendBody(
                content: content,
                images: imageBodies.isEmpty ? nil : imageBodies,
                pageContext: StormAiPageContextBody(
                    pathname: visitId.map { "ios://visit/\($0)" } ?? "ios://more",
                    visitId: visitId
                )
            )
            let result: StormAiMessagesResponse = try await env.apiClient.post(
                path: APIPath.stormAiMessages(conversationId),
                body: body,
                timeoutInterval: photos.isEmpty ? 60 : 120
            )
            messages = result.messages
            warning = result.warning
            await loadHistory()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
