import Foundation

struct VisitDTO: Decodable, Identifiable, Hashable {
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

    enum CodingKeys: String, CodingKey {
        case id, title, startAt, endAt, division, status, tags, isCallback
        case address, city, state, zip, customer, property, serviceArea
        case assignedUser, crew, subtotal, total, enRouteEtaSeconds, enRouteEtaAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startAt = try Self.decodeDateString(from: container, forKey: .startAt)
        endAt = try Self.decodeDateString(from: container, forKey: .endAt)
        division = try container.decode(String.self, forKey: .division)
        status = try container.decode(String.self, forKey: .status)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        isCallback = try container.decodeIfPresent(Bool.self, forKey: .isCallback)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        zip = try container.decodeIfPresent(String.self, forKey: .zip)
        customer = try container.decodeIfPresent(CustomerSummary.self, forKey: .customer)
        property = try container.decodeIfPresent(PropertySummary.self, forKey: .property)
        serviceArea = try container.decodeIfPresent(NamedColor.self, forKey: .serviceArea)
        assignedUser = try container.decodeIfPresent(NamedColor.self, forKey: .assignedUser)
        crew = try container.decodeIfPresent(NamedColor.self, forKey: .crew)
        subtotal = try container.decodeFlexibleDouble(forKey: .subtotal)
        total = try container.decodeFlexibleDouble(forKey: .total)
        enRouteEtaSeconds = try container.decodeIfPresent(Int.self, forKey: .enRouteEtaSeconds)
        enRouteEtaAt = try Self.decodeOptionalDateString(from: container, forKey: .enRouteEtaAt)
    }

    private static func decodeDateString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String {
        if let text = try container.decodeIfPresent(String.self, forKey: key) {
            return text
        }
        if let date = try container.decodeIfPresent(Date.self, forKey: key) {
            return APIDateFormatting.queryString(from: date)
        }
        throw DecodingError.keyNotFound(key, .init(codingPath: container.codingPath, debugDescription: "Missing date"))
    }

    private static func decodeOptionalDateString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String? {
        if (try? container.decodeNil(forKey: key)) == true { return nil }
        if let text = try container.decodeIfPresent(String.self, forKey: key) {
            return text
        }
        if let date = try container.decodeIfPresent(Date.self, forKey: key) {
            return APIDateFormatting.queryString(from: date)
        }
        return nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: VisitDTO, rhs: VisitDTO) -> Bool {
        lhs.id == rhs.id
    }
}

struct VisitsListResponse: Decodable {
    let visits: [VisitDTO]
}

struct CustomersListResponse: Decodable {
    let customers: [CustomerDTO]
}

struct VisitDetailDTO: Decodable, Identifiable {
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

struct PropertySummary: Decodable, Hashable {
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

    enum CodingKeys: String, CodingKey {
        case id, name, address, city, state, zip, latitude, longitude
        case aerialImageUrl, propertyDiagramUrl, irrigationMapStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        zip = try container.decodeIfPresent(String.self, forKey: .zip)
        latitude = try container.decodeFlexibleDouble(forKey: .latitude)
        longitude = try container.decodeFlexibleDouble(forKey: .longitude)
        aerialImageUrl = try container.decodeIfPresent(String.self, forKey: .aerialImageUrl)
        propertyDiagramUrl = try container.decodeIfPresent(String.self, forKey: .propertyDiagramUrl)
        irrigationMapStatus = try container.decodeIfPresent(String.self, forKey: .irrigationMapStatus)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PropertySummary, rhs: PropertySummary) -> Bool {
        lhs.id == rhs.id
    }
}

struct NamedColor: Codable, Hashable {
    let id: String
    let name: String
    let color: String?
    let photoUrl: String?
}

struct LineItemDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let quantity: Double
    let unitPrice: Double
    let total: Double

    enum CodingKeys: String, CodingKey {
        case id, name, description, quantity, unitPrice, total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        quantity = try container.decodeFlexibleDouble(forKey: .quantity) ?? 0
        unitPrice = try container.decodeFlexibleDouble(forKey: .unitPrice) ?? 0
        total = try container.decodeFlexibleDouble(forKey: .total) ?? 0
    }
}

struct DiscountDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let amount: Double
    let type: String

    enum CodingKeys: String, CodingKey {
        case id, name, label, amount, type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? (try container.decodeIfPresent(String.self, forKey: .label))
            ?? "Discount"
        amount = try container.decodeFlexibleDouble(forKey: .amount) ?? 0
        type = try container.decode(String.self, forKey: .type)
    }
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

struct InvoiceSummaryDTO: Decodable, Identifiable {
    let id: String
    let invoiceNumber: String
    let status: String
    let total: Double
    let paidAt: String?

    enum CodingKeys: String, CodingKey {
        case id, invoiceNumber, status, total, paidAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        invoiceNumber = try container.decode(String.self, forKey: .invoiceNumber)
        status = try container.decode(String.self, forKey: .status)
        total = try container.decodeFlexibleDouble(forKey: .total) ?? 0
        if let text = try container.decodeIfPresent(String.self, forKey: .paidAt) {
            paidAt = text
        } else if let date = try container.decodeIfPresent(Date.self, forKey: .paidAt) {
            paidAt = APIDateFormatting.queryString(from: date)
        } else {
            paidAt = nil
        }
    }
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

struct ConversationDTO: Decodable, Identifiable {
    let id: String
    let title: String?
    let participantPhone: String?
    let lastMessageAt: String?
    let customer: CustomerSummary?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        participantPhone = try container.decodeIfPresent(String.self, forKey: .participantPhone)
        customer = try container.decodeIfPresent(CustomerSummary.self, forKey: .customer)
        if let text = try container.decodeIfPresent(String.self, forKey: .lastMessageAt) {
            lastMessageAt = text
        } else if let date = try container.decodeIfPresent(Date.self, forKey: .lastMessageAt) {
            lastMessageAt = APIDateFormatting.queryString(from: date)
        } else {
            lastMessageAt = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, participantPhone, lastMessageAt, customer
    }
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
    let companyName: String?
    let status: String?
}
