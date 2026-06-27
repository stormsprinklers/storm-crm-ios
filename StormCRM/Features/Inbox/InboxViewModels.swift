import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum InboxScope: String, CaseIterable, Identifiable {
    case customers
    case team

    var id: String { rawValue }

    var apiScope: String {
        switch self {
        case .customers: return "external"
        case .team: return "internal"
        }
    }

    var title: String {
        switch self {
        case .customers: return "Customers"
        case .team: return "Team"
        }
    }
}

struct PendingOutboxAttachment: Identifiable {
    let id = UUID()
    let blobUrl: String
    let publicUrl: String?
    let fileName: String
    let mimeType: String
    let sizeBytes: Int
    let previewImage: UIImage?
}

@MainActor
final class InboxListViewModel: ObservableObject {
    @Published var conversations: [ConversationDTO] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(api: APIClient, scope: InboxScope) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            conversations = try await api.get(
                path: APIPath.smsConversations,
                query: [URLQueryItem(name: "scope", value: scope.apiScope)]
            )
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

@MainActor
final class SmsConversationViewModel: ObservableObject {
    @Published var messages: [MessageDTO] = []
    @Published var conversation: ConversationDTO?
    @Published var draft = ""
    @Published var attachments: [PendingOutboxAttachment] = []
    @Published var isSending = false
    @Published var isUploading = false
    @Published var error: String?

    private var pollTask: Task<Void, Never>?

    func startPolling(api: APIClient, conversationId: String) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                await load(api: api, conversationId: conversationId, silent: true)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func load(api: APIClient, conversationId: String, silent: Bool = false) async {
        if !silent { error = nil }
        do {
            let response: MessagesResponse = try await api.get(path: APIPath.smsMessages(conversationId))
            conversation = response.conversation
            messages = response.messages
        } catch {
            if !silent {
                self.error = (error as? APIError)?.message ?? error.localizedDescription
            }
        }
    }

    func send(api: APIClient, conversationId: String, scope: InboxScope) async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || !attachments.isEmpty else { return }
        guard let phone = conversation?.participantPhone else {
            error = "No recipient phone on conversation"
            return
        }

        struct MediaPayload: Encodable {
            let blobUrl: String
            let fileName: String
            let mimeType: String
            let sizeBytes: Int
            let publicUrl: String?
        }
        struct Body: Encodable {
            let to: String
            let body: String
            let scope: String
            let title: String?
            let customerId: String?
            let media: [MediaPayload]
        }

        isSending = true
        error = nil
        defer { isSending = false }

        do {
            let _: SendSmsResponse = try await api.post(
                path: APIPath.smsConversations,
                body: Body(
                    to: phone,
                    body: body,
                    scope: scope.apiScope,
                    title: conversation?.title,
                    customerId: conversation?.customer?.id,
                    media: attachments.map {
                        MediaPayload(
                            blobUrl: $0.blobUrl,
                            fileName: $0.fileName,
                            mimeType: $0.mimeType,
                            sizeBytes: $0.sizeBytes,
                            publicUrl: $0.publicUrl
                        )
                    }
                )
            )
            draft = ""
            attachments = []
            await load(api: api, conversationId: conversationId)
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func uploadAttachment(api: APIClient, data: Data, fileName: String, mimeType: String) async {
        isUploading = true
        defer { isUploading = false }
        do {
            let response: InboxMediaUploadResponse = try await api.uploadMultipart(
                path: APIPath.inboxMediaUpload,
                query: [URLQueryItem(name: "channel", value: "sms")],
                fileData: data,
                fileName: fileName,
                mimeType: mimeType
            )
            let preview = mimeType.hasPrefix("image/") ? UIImage(data: data) : nil
            attachments.append(
                PendingOutboxAttachment(
                    blobUrl: response.blobUrl,
                    publicUrl: response.publicUrl,
                    fileName: response.fileName,
                    mimeType: response.mimeType,
                    sizeBytes: response.sizeBytes,
                    previewImage: preview
                )
            )
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func removeAttachment(_ attachment: PendingOutboxAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }
}

@MainActor
final class NewSmsConversationViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var customerResults: [InboxContactDTO] = []
    @Published var employeeResults: [InboxEmployeeContactDTO] = []
    @Published var selectedCustomer: InboxContactDTO?
    @Published var selectedEmployee: InboxEmployeeContactDTO?
    @Published var draft = ""
    @Published var attachments: [PendingOutboxAttachment] = []
    @Published var isSending = false
    @Published var isSearching = false
    @Published var isUploading = false
    @Published var error: String?

    func search(api: APIClient, scope: InboxScope) async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            customerResults = []
            employeeResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            if scope == .customers {
                let response: InboxCustomerContactsResponse = try await api.get(
                    path: APIPath.inboxContacts,
                    query: [
                        URLQueryItem(name: "for", value: "sms"),
                        URLQueryItem(name: "search", value: query),
                    ]
                )
                customerResults = response.customers
            } else {
                let response: InboxEmployeeContactsResponse = try await api.get(
                    path: APIPath.inboxContacts,
                    query: [
                        URLQueryItem(name: "scope", value: "internal"),
                        URLQueryItem(name: "for", value: "sms"),
                        URLQueryItem(name: "search", value: query),
                    ]
                )
                employeeResults = response.employees
            }
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func send(api: APIClient, scope: InboxScope) async -> String? {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || !attachments.isEmpty else { return nil }

        let phone: String?
        let title: String?
        let customerId: String?
        let userId: String?

        if scope == .customers {
            guard let customer = selectedCustomer, let customerPhone = customer.phone else {
                error = "Select a customer with a phone number"
                return nil
            }
            phone = customerPhone
            title = customer.name
            customerId = customer.id
            userId = nil
        } else {
            guard let employee = selectedEmployee, let employeePhone = employee.phone else {
                error = "Select a team member with a phone number"
                return nil
            }
            phone = employeePhone
            title = employee.name
            customerId = nil
            userId = employee.id
        }

        struct MediaPayload: Encodable {
            let blobUrl: String
            let fileName: String
            let mimeType: String
            let sizeBytes: Int
            let publicUrl: String?
        }
        struct Body: Encodable {
            let to: String
            let body: String
            let scope: String
            let title: String?
            let customerId: String?
            let userId: String?
            let media: [MediaPayload]
        }

        isSending = true
        error = nil
        defer { isSending = false }

        do {
            let response: SendSmsResponse = try await api.post(
                path: APIPath.smsConversations,
                body: Body(
                    to: phone!,
                    body: body,
                    scope: scope.apiScope,
                    title: title,
                    customerId: customerId,
                    userId: userId,
                    media: attachments.map {
                        MediaPayload(
                            blobUrl: $0.blobUrl,
                            fileName: $0.fileName,
                            mimeType: $0.mimeType,
                            sizeBytes: $0.sizeBytes,
                            publicUrl: $0.publicUrl
                        )
                    }
                )
            )
            return response.conversation.id
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
            return nil
        }
    }

    func uploadAttachment(api: APIClient, data: Data, fileName: String, mimeType: String) async {
        isUploading = true
        defer { isUploading = false }
        do {
            let response: InboxMediaUploadResponse = try await api.uploadMultipart(
                path: APIPath.inboxMediaUpload,
                query: [URLQueryItem(name: "channel", value: "sms")],
                fileData: data,
                fileName: fileName,
                mimeType: mimeType
            )
            let preview = mimeType.hasPrefix("image/") ? UIImage(data: data) : nil
            attachments.append(
                PendingOutboxAttachment(
                    blobUrl: response.blobUrl,
                    publicUrl: response.publicUrl,
                    fileName: response.fileName,
                    mimeType: response.mimeType,
                    sizeBytes: response.sizeBytes,
                    previewImage: preview
                )
            )
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
