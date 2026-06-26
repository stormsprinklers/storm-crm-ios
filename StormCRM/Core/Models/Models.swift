import Foundation

struct VisitDTO: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let startAt: String
    let endAt: String
    let division: String
    let status: String
    let tags: [String]?
    let isCallback: Bool?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let customer: CustomerSummary?
    let property: PropertySummary?
    let serviceArea: NamedColor?
    let assignedUser: NamedColor?
    let crew: NamedColor?
    let subtotal: Double?
    let total: Double?
    let enRouteEtaSeconds: Int?
    let enRouteEtaAt: String?
}

struct VisitDetailDTO: Codable, Identifiable {
    let id: String
    let title: String
    let startAt: String
    let endAt: String
    let division: String
    let status: String
    let tags: [String]?
    let isCallback: Bool?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let customer: CustomerSummary?
    let property: PropertySummary?
    let serviceArea: NamedColor?
    let assignedUser: NamedColor?
    let crew: NamedColor?
    let lineItems: [LineItemDTO]?
    let discounts: [DiscountDTO]?
    let timeEvents: [TimeEventDTO]?
    let notes: [VisitNoteDTO]?
    let attachments: [AttachmentDTO]?
    let invoices: [InvoiceSummaryDTO]?
    let total: Double?
    let subtotal: Double?
    let eta: ETADTO?
}

struct CustomerSummary: Codable, Hashable {
    let id: String
    let name: String
    let phone: String?
    let email: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let doNotService: Bool?
}

struct PropertySummary: Codable, Hashable {
    let id: String
    let name: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let latitude: Double?
    let longitude: Double?
    let aerialImageUrl: String?
    let propertyDiagramUrl: String?
    let irrigationMapStatus: String?
}

struct NamedColor: Codable, Hashable {
    let id: String
    let name: String
    let color: String?
    let photoUrl: String?
}

struct LineItemDTO: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let quantity: Double
    let unitPrice: Double
    let total: Double
}

struct DiscountDTO: Codable, Identifiable {
    let id: String
    let name: String
    let amount: Double
    let type: String
}

struct TimeEventDTO: Codable, Identifiable {
    let id: String
    let type: String
    let occurredAt: String
    let user: NamedColor?
}

struct VisitNoteDTO: Codable, Identifiable {
    let id: String
    let body: String
    let createdAt: String
    let author: NamedColor?
}

struct AttachmentDTO: Codable, Identifiable {
    let id: String
    let fileName: String
    let mimeType: String
    let blobUrl: String
    let createdAt: String
}

struct InvoiceSummaryDTO: Codable, Identifiable {
    let id: String
    let invoiceNumber: String
    let status: String
    let total: Double
    let paidAt: String?
}

struct ETADTO: Codable {
    let seconds: Int?
    let formatted: String?
}

struct ActiveVisitResponse: Decodable {
    let visit: VisitDetailDTO?
}

struct TimeEventsResponse: Decodable {
    let events: [TimeEventDTO]?
}

struct ChecklistDTO: Codable, Identifiable {
    let id: String
    let name: String
    let items: [ChecklistItemDTO]
    let completedAt: String?
}

struct ChecklistItemDTO: Codable, Identifiable {
    let id: String
    let label: String
    let type: String?
    let sortOrder: Int?
    let response: JSONValue?
    let completedAt: String?

    var isCompleted: Bool {
        if completedAt != nil { return true }
        if case .bool(let value) = response { return value }
        if case .string(let value) = response { return !value.isEmpty }
        return false
    }
}

/// Lightweight JSON for checklist item responses.
enum JSONValue: Codable, Equatable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct PartsRunGetResponse: Decodable {
    let options: [PartsRunOptionDTO]?
    let message: String?
}

struct PartsRunPostResponse: Decodable {
    let paused: Bool?
    let mapsUrl: String?
}

struct PartsRunOptionDTO: Codable, Identifiable {
    var id: String { supplierId }
    let supplierId: String
    let name: String
    let address: String?
    let phone: String?
    let driveDistanceMiles: Double?
    let mapsUrl: String?
}

struct IrrigationMapDTO: Decodable {
    let imageUrl: String?
    let zones: [IrrigationZoneDTO]?
    let status: String?
}

struct IrrigationZoneDTO: Codable, Identifiable {
    let id: String
    let label: String?
    let color: String?
}

struct IrrigationProgramDTO: Decodable {
    let zones: [ProgramZoneDTO]?
    let notes: String?
}

struct ProgramZoneDTO: Codable, Identifiable {
    let id: String
    let name: String?
    let runTimes: [String]?
}

struct ConversationDTO: Codable, Identifiable {
    let id: String
    let title: String?
    let participantPhone: String?
    let lastMessageAt: String?
    let customer: CustomerSummary?
}

struct MessagesResponse: Decodable {
    let conversation: ConversationDTO
    let messages: [MessageDTO]
}

struct MessageDTO: Codable, Identifiable {
    let id: String
    let body: String?
    let direction: String?
    let sentAt: String?
    let createdAt: String?

    var displayDate: String { sentAt ?? createdAt ?? "" }
}

struct TimeClockResponse: Decodable {
    let openEntry: ClockEntryDTO?
    let todayHours: Double?
    let todayEntries: [ClockEntryDTO]?
}

struct ClockEntryDTO: Codable, Identifiable {
    let id: String
    let clockInAt: String
    let clockOutAt: String?
    let durationHours: Double?
}

struct CheckoutResponse: Decodable {
    let url: String?
    let payLink: String?
}

struct CustomerDTO: Codable, Identifiable {
    let id: String
    let name: String
    let phone: String?
    let email: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
}
