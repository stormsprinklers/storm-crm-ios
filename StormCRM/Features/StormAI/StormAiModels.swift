import Foundation

struct StormAiConversationDTO: Decodable, Identifiable {
    let id: String
    let title: String?
    let createdAt: String?
    let updatedAt: String?
}

struct StormAiAttachmentDTO: Decodable, Hashable {
    let fileName: String
    let mimeType: String
    let kind: String
    let url: String
}

struct StormAiPartsCardPhotoDTO: Decodable, Hashable {
    let id: String?
    let url: String
    let fileName: String
}

struct StormAiPartsCardDTO: Decodable, Hashable, Identifiable {
    let kind: String
    let partId: String
    let name: String
    let manufacturer: String?
    let partNumber: String?
    let section: String?
    let visualDescription: String?
    let technicalDescription: String?
    let manualUrl: String?
    let manualKind: String?
    let photos: [StormAiPartsCardPhotoDTO]

    var id: String { partId }
}

struct StormAiMessageDTO: Decodable, Identifiable {
    let id: String
    let role: String
    let content: String
    let createdAt: String
    let attachments: [StormAiAttachmentDTO]?
    let partsCard: StormAiPartsCardDTO?

    var isUser: Bool { role == "user" }

    init(
        id: String,
        role: String,
        content: String,
        createdAt: String,
        attachments: [StormAiAttachmentDTO]?,
        partsCard: StormAiPartsCardDTO? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.attachments = attachments
        self.partsCard = partsCard
    }
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

struct StormAiSendImageBody: Encodable {
    let dataUrl: String
    let fileName: String
    let mimeType: String
}

struct StormAiSendBody: Encodable {
    let content: String
    let images: [StormAiSendImageBody]?
    let pageContext: StormAiPageContextBody
}

struct StormAiPageContextBody: Encodable {
    let pathname: String
    let visitId: String?
    let customerId: String?

    init(pathname: String, visitId: String? = nil, customerId: String? = nil) {
        self.pathname = pathname
        self.visitId = visitId
        self.customerId = customerId
    }
}

struct StormAiRealtimeSessionBody: Encodable {
    let conversationId: String?
    let pageContext: StormAiPageContextBody
    let videoMode: Bool?
}

struct StormAiRealtimeSessionResponse: Decodable {
    let conversationId: String
    let clientSecret: String
    let model: String?
    let voice: String?
    let expiresAt: Double?
}

struct StormAiRealtimeToolBody: Encodable {
    let conversationId: String
    let callId: String
    let name: String
    let arguments: [String: StormAiJSONValue]?
}

/// JSON value tree for realtime tool arguments (avoid clashing with OfflineSyncManager.AnyCodableValue).
enum StormAiJSONValue: Encodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([StormAiJSONValue])
    case object([String: StormAiJSONValue])

    init(from json: Any) {
        switch json {
        case let v as String: self = .string(v)
        case let v as Bool: self = .bool(v)
        case let v as Int: self = .int(v)
        case let v as Double: self = .double(v)
        case let v as NSNumber:
            // JSONSerialization often boxes numbers/bools as NSNumber
            if CFGetTypeID(v) == CFBooleanGetTypeID() {
                self = .bool(v.boolValue)
            } else if abs(v.doubleValue.truncatingRemainder(dividingBy: 1)) < .ulpOfOne {
                self = .int(v.intValue)
            } else {
                self = .double(v.doubleValue)
            }
        case let v as [Any]: self = .array(v.map(StormAiJSONValue.init(from:)))
        case let v as [String: Any]:
            self = .object(v.mapValues { StormAiJSONValue(from: $0) })
        case is NSNull: self = .null
        default: self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}
