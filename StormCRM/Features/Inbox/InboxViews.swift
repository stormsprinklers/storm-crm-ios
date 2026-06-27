import PhotosUI
import SwiftUI

struct InboxHubView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var push = PushNotificationManager.shared
    @State private var scope: InboxScope = .customers
    @State private var navigationPath = NavigationPath()
    @State private var showCompose = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            InboxListView(scope: scope)
                .navigationTitle("Inbox")
                .onAppear {
                    if let role = env.auth.user?.role, UserRoles.isFieldRole(role) {
                        scope = .team
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showCompose = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    Picker("Inbox", selection: $scope) {
                        ForEach(InboxScope.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(StormTheme.page)
                }
                .navigationDestination(for: String.self) { conversationId in
                    SmsConversationView(conversationId: conversationId, scope: scope)
                }
                .sheet(isPresented: $showCompose) {
                    NavigationStack {
                        NewSmsConversationView(scope: scope) { conversationId in
                            showCompose = false
                            navigationPath.append(conversationId)
                        }
                    }
                }
                .onChange(of: push.pendingConversationId) { _, conversationId in
                    guard let conversationId else { return }
                    navigationPath.append(conversationId)
                    push.pendingConversationId = nil
                }
                .onChange(of: env.pendingInboxConversationId) { _, conversationId in
                    guard let conversationId else { return }
                    navigationPath.append(conversationId)
                    env.pendingInboxConversationId = nil
                }
        }
    }
}

struct InboxListView: View {
    @EnvironmentObject private var env: AppEnvironment
    let scope: InboxScope
    @StateObject private var viewModel = InboxListViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.conversations.isEmpty {
                ProgressView("Loading inbox…")
            } else if let error = viewModel.error {
                ContentUnavailableView(
                    "Could not load inbox",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if viewModel.conversations.isEmpty {
                ContentUnavailableView("No conversations", systemImage: "message")
            } else {
                List(viewModel.conversations) { conversation in
                    NavigationLink(value: conversation.id) {
                        InboxConversationRow(conversation: conversation)
                    }
                }
                .listStyle(.plain)
            }
        }
        .refreshable { await viewModel.load(api: env.apiClient, scope: scope) }
        .task(id: scope) { await viewModel.load(api: env.apiClient, scope: scope) }
    }
}

struct InboxConversationRow: View {
    let conversation: ConversationDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if let lastMessageAt = conversation.lastMessageAt {
                    Text(relativeDate(lastMessageAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let preview = conversation.previewText, !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let phone = conversation.participantPhone,
               conversation.customer?.name != nil,
               phone != conversation.displayTitle {
                Text(phone)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func relativeDate(_ iso: String) -> String {
        guard let date = APIDateFormatting.parse(iso) else {
            return APIDateFormatting.displayString(from: iso)
        }
        return date.formatted(.relative(presentation: .named))
    }
}

struct SmsConversationView: View {
    @EnvironmentObject private var env: AppEnvironment
    let conversationId: String
    let scope: InboxScope
    @StateObject private var viewModel = SmsConversationViewModel()
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            SmsMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let last = viewModel.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if !viewModel.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.attachments) { attachment in
                            OutboxAttachmentChip(attachment: attachment) {
                                viewModel.removeAttachment(attachment)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 8)
            }

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .any(of: [.images, .videos])) {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .padding(8)
                }
                .disabled(viewModel.isUploading)

                TextField("Message", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await viewModel.send(api: env.apiClient, conversationId: conversationId, scope: scope) }
                } label: {
                    if viewModel.isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .disabled(viewModel.isSending || viewModel.isUploading ||
                          (viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.attachments.isEmpty))
            }
            .padding()

            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle(viewModel.conversation?.displayTitle ?? "Messages")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load(api: env.apiClient, conversationId: conversationId)
            viewModel.startPolling(api: env.apiClient, conversationId: conversationId)
        }
        .onDisappear { viewModel.stopPolling() }
        .onChange(of: photoItems) { _, items in
            Task { await importPhotos(items, api: env.apiClient) }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem], api: APIClient) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "application/octet-stream"
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                await viewModel.uploadAttachment(api: api, data: data, fileName: "attachment.\(ext)", mimeType: mime)
            }
        }
        photoItems = []
    }
}

struct SmsMessageBubble: View {
    let message: MessageDTO

    var body: some View {
        HStack(alignment: .bottom) {
            if message.isOutbound { Spacer(minLength: 48) }
            VStack(alignment: message.isOutbound ? .trailing : .leading, spacing: 4) {
                if message.isOutbound, let senderName = message.sender?.name, !senderName.isEmpty {
                    Text(senderName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    if let media = message.media, !media.isEmpty {
                        MessageMediaGalleryView(media: media)
                    }
                    if let body = message.body, !body.isEmpty, body != "[Media message]" {
                        Text(body)
                    }
                }
                .padding(10)
                .background(message.isOutbound ? StormTheme.coral.opacity(0.18) : Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                HStack(spacing: 6) {
                    Text(APIDateFormatting.displayString(from: message.displayDate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if message.isOutbound, let status = message.deliveryStatus, !status.isEmpty {
                        Text(status.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            if !message.isOutbound { Spacer(minLength: 48) }
        }
    }
}

struct NewSmsConversationView: View {
    @EnvironmentObject private var env: AppEnvironment
    let scope: InboxScope
    var initialContact: InboxContactDTO?
    let onSent: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = NewSmsConversationViewModel()
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        Form {
            Section("Recipient") {
                TextField(scope == .customers ? "Search customers" : "Search team", text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await viewModel.search(api: env.apiClient, scope: scope) } }

                if viewModel.isSearching {
                    ProgressView()
                }

                if scope == .customers {
                    ForEach(viewModel.customerResults) { customer in
                        Button {
                            viewModel.selectedCustomer = customer
                            viewModel.selectedEmployee = nil
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(customer.name)
                                    if let phone = customer.phone {
                                        Text(phone).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if viewModel.selectedCustomer?.id == customer.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(StormTheme.coral)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    ForEach(viewModel.employeeResults) { employee in
                        Button {
                            viewModel.selectedEmployee = employee
                            viewModel.selectedCustomer = nil
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(employee.name)
                                    if let phone = employee.phone {
                                        Text(phone).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if viewModel.selectedEmployee?.id == employee.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(StormTheme.coral)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Message") {
                TextField("Type a message", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(3...6)

                if !viewModel.attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(viewModel.attachments) { attachment in
                                OutboxAttachmentChip(attachment: attachment) {
                                    viewModel.attachments.removeAll { $0.id == attachment.id }
                                }
                            }
                        }
                    }
                }

                PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .any(of: [.images, .videos])) {
                    Label("Add photo or video", systemImage: "paperclip")
                }
            }

            if let error = viewModel.error {
                Section {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .navigationTitle("New message")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Send") {
                    Task {
                        if let conversationId = await viewModel.send(api: env.apiClient, scope: scope) {
                            onSent(conversationId)
                        }
                    }
                }
                .disabled(viewModel.isSending || viewModel.isUploading)
            }
        }
        .onAppear {
            if scope == .customers, let contact = initialContact {
                viewModel.selectedCustomer = contact
                viewModel.searchText = contact.name
            }
        }
        .onChange(of: viewModel.searchText) { _, text in
            guard text.count >= 2 else { return }
            Task { await viewModel.search(api: env.apiClient, scope: scope) }
        }
        .onChange(of: photoItems) { _, items in
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "application/octet-stream"
                        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                        await viewModel.uploadAttachment(
                            api: env.apiClient,
                            data: data,
                            fileName: "attachment.\(ext)",
                            mimeType: mime
                        )
                    }
                }
                photoItems = []
            }
        }
    }
}

struct OutboxAttachmentChip: View {
    let attachment: PendingOutboxAttachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let preview = attachment.previewImage {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                } else if attachment.mimeType.hasPrefix("video/") {
                    ZStack {
                        StormTheme.ice.opacity(0.4)
                        Image(systemName: "video.fill")
                    }
                } else {
                    ZStack {
                        StormTheme.ice.opacity(0.4)
                        Image(systemName: "doc.fill")
                    }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .offset(x: 6, y: -6)
        }
    }
}
