import Foundation

struct StormAiConversationDTO: Decodable, Identifiable {
    let id: String
    let title: String?
    let createdAt: String?
    let updatedAt: String?
}

struct StormAiMessageDTO: Decodable, Identifiable {
    let id: String
    let role: String
    let content: String
    let createdAt: String

    var isUser: Bool { role == "user" }
}

struct StormAiConversationListResponse: Decodable {
    let conversations: [StormAiConversationDTO]
}

struct StormAiConversationCreatedResponse: Decodable {
    let conversation: StormAiConversationDTO
}

struct StormAiConversationDetailResponse: Decodable {
    let conversation: StormAiConversationDetailDTO
}

struct StormAiConversationDetailDTO: Decodable {
    let id: String
    let title: String?
    let messages: [StormAiMessageDTO]
}

struct StormAiMessagesResponse: Decodable {
    let messages: [StormAiMessageDTO]
    let warning: String?
}

struct StormAiSendBody: Encodable {
    let content: String
    let pageContext: StormAiPageContextBody
}

struct StormAiPageContextBody: Encodable {
    let pathname: String
}
