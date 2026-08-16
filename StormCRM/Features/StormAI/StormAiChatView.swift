import SwiftUI

struct StormAiChatView: View {
    @EnvironmentObject private var env: AppEnvironment

    @State private var conversationId: String?
    @State private var messages: [StormAiMessageDTO] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var isLoading = true
    @State private var error: String?
    @State private var warning: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if isLoading && messages.isEmpty {
                            ProgressView("Loading…")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 24)
                        } else if messages.isEmpty && !isSending {
                            Text("Ask about customers, the schedule, or performance. I only use CRM facts.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
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

            HStack(alignment: .bottom, spacing: 8) {
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
                .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    Task { await startNewChat() }
                }
                .disabled(isSending)
            }
        }
        .task { await loadLatest() }
    }

    private func stormBubble(_ message: StormAiMessageDTO) -> some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }
            Group {
                if let attributed = try? AttributedString(markdown: message.content) {
                    Text(attributed)
                } else {
                    Text(message.content)
                }
            }
            .font(.subheadline)
            .foregroundStyle(message.isUser ? StormTheme.navy : StormTheme.navy)
            .padding(12)
            .background(message.isUser ? StormTheme.sky.opacity(0.18) : Color(.secondarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !message.isUser { Spacer(minLength: 40) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if isSending {
            proxy.scrollTo("thinking", anchor: .bottom)
        } else if let last = messages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func loadLatest() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let list: StormAiConversationListResponse = try await env.apiClient.get(
                path: APIPath.stormAiConversations
            )
            guard let latest = list.conversations.first else { return }
            conversationId = latest.id
            let detail: StormAiConversationDetailResponse = try await env.apiClient.get(
                path: APIPath.stormAiConversation(latest.id)
            )
            messages = detail.conversation.messages
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func startNewChat() async {
        error = nil
        warning = nil
        do {
            let created: StormAiConversationCreatedResponse = try await env.apiClient.post(
                path: APIPath.stormAiConversations
            )
            conversationId = created.conversation.id
            messages = []
            draft = ""
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func send() async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        error = nil
        warning = nil
        draft = ""
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

            messages.append(
                StormAiMessageDTO(
                    id: "local-\(UUID().uuidString)",
                    role: "user",
                    content: content,
                    createdAt: ISO8601DateFormatter().string(from: Date())
                )
            )

            let body = StormAiSendBody(
                content: content,
                pageContext: StormAiPageContextBody(pathname: "ios://more")
            )
            let result: StormAiMessagesResponse = try await env.apiClient.post(
                path: APIPath.stormAiMessages(conversationId),
                body: body
            )
            messages = result.messages
            warning = result.warning
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
