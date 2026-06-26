import SwiftUI

@MainActor
final class TeamInboxViewModel: ObservableObject {
    @Published var conversations: [ConversationDTO] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(api: APIClient) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            conversations = try await api.get(path: APIPath.smsConversations)
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct TeamInboxView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var viewModel = TeamInboxViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.conversations.isEmpty {
                    ProgressView("Loading inbox…")
                } else if let error = viewModel.error {
                    ContentUnavailableView("Could not load inbox", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if viewModel.conversations.isEmpty {
                    ContentUnavailableView("No conversations", systemImage: "message")
                } else {
                    List(viewModel.conversations) { conversation in
                        NavigationLink(value: conversation.id) {
                            ConversationRow(conversation: conversation)
                        }
                    }
                }
            }
            .navigationTitle("Inbox")
            .navigationDestination(for: String.self) { conversationId in
                ConversationView(conversationId: conversationId)
            }
            .refreshable { await viewModel.load(api: env.apiClient) }
            .task { await viewModel.load(api: env.apiClient) }
        }
    }
}

struct ConversationRow: View {
    let conversation: ConversationDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.title ?? conversation.customer?.name ?? conversation.participantPhone ?? "Conversation")
                .font(.headline)
            if let customer = conversation.customer, conversation.title != nil {
                Text(customer.name).foregroundStyle(.secondary)
            } else if let phone = conversation.participantPhone, conversation.customer == nil {
                Text(phone).foregroundStyle(.secondary)
            }
            if let lastMessageAt = conversation.lastMessageAt {
                Text(formatDate(lastMessageAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

@MainActor
final class ConversationViewModel: ObservableObject {
    @Published var messages: [MessageDTO] = []
    @Published var conversation: ConversationDTO?
    @Published var draft = ""
    @Published var error: String?

    func load(api: APIClient, conversationId: String) async {
        do {
            let response: MessagesResponse = try await api.get(path: APIPath.smsMessages(conversationId))
            conversation = response.conversation
            messages = response.messages
        } catch {
            error = (error as? APIError)?.message
        }
    }

    func send(api: APIClient, conversationId: String) async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        guard let phone = conversation?.participantPhone else {
            error = "No recipient phone on conversation"
            return
        }
        struct Body: Encodable {
            let to: String
            let body: String
            let scope: String
            let title: String?
        }
        do {
            let _: EmptyResponse = try await api.post(
                path: APIPath.smsConversations,
                body: Body(
                    to: phone,
                    body: body,
                    scope: "internal",
                    title: conversation?.title
                )
            )
            draft = ""
            await load(api: api, conversationId: conversationId)
        } catch {
            error = (error as? APIError)?.message
        }
    }
}

struct ConversationView: View {
    @EnvironmentObject private var env: AppEnvironment
    let conversationId: String
    @StateObject private var viewModel = ConversationViewModel()

    var body: some View {
        VStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.messages) { message in
                        let outbound = message.direction == "OUTBOUND"
                        HStack {
                            if outbound { Spacer() }
                            Text(message.body ?? "")
                                .padding(10)
                                .background(outbound ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            if !outbound { Spacer() }
                        }
                    }
                }
                .padding()
            }
            HStack {
                TextField("Message", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...4)
                Button("Send") {
                    Task { await viewModel.send(api: env.apiClient, conversationId: conversationId) }
                }
            }
            .padding()
            if let error = viewModel.error {
                Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }
        }
        .navigationTitle(viewModel.conversation?.title ?? "Messages")
        .task { await viewModel.load(api: env.apiClient, conversationId: conversationId) }
    }
}
