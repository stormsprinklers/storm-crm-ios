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
    let workSummary: String?
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
    let estimates: [EstimateSummaryDTO]?
    let total: Double?
    let subtotal: Double?
    let eta: ETADTO?
    let designProjectId: String?
    let installDurationDays: Int?
    let designExportMetadata: JSONValue?

    var hasInstallPlan: Bool {
        designExportMetadata != nil && designExportMetadata != .null
    }
}

struct EstimateSummaryDTO: Decodable, Identifiable {
    let id: String
    let estimateNumber: String?
    let displayNumber: String?
    let status: String
    let total: Double
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, estimateNumber, displayNumber, status, total, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        estimateNumber = try container.decodeIfPresent(String.self, forKey: .estimateNumber)
        displayNumber = try container.decodeIfPresent(String.self, forKey: .displayNumber)
        status = try container.decode(String.self, forKey: .status)
        total = try container.decodeFlexibleDouble(forKey: .total) ?? 0
        if let text = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = text
        } else if let date = try container.decodeIfPresent(Date.self, forKey: .createdAt) {
            createdAt = APIDateFormatting.queryString(from: date)
        } else {
            createdAt = ""
        }
    }

    var titleLabel: String {
        displayNumber ?? estimateNumber ?? "Estimate"
    }
}

struct InvoicePaymentDTO: Decodable {
    let amount: Double
    let refundedAt: String?

    enum CodingKeys: String, CodingKey {
        case amount, refundedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amount = try container.decodeFlexibleDouble(forKey: .amount) ?? 0
        if let text = try container.decodeIfPresent(String.self, forKey: .refundedAt) {
            refundedAt = text
        } else if let date = try container.decodeIfPresent(Date.self, forKey: .refundedAt) {
            refundedAt = APIDateFormatting.queryString(from: date)
        } else {
            refundedAt = nil
        }
    }
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

    init(
        id: String,
        name: String?,
        address: String?,
        city: String?,
        state: String?,
        zip: String?,
        latitude: Double? = nil,
        longitude: Double? = nil,
        aerialImageUrl: String? = nil,
        propertyDiagramUrl: String? = nil,
        irrigationMapStatus: String? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.city = city
        self.state = state
        self.zip = zip
        self.latitude = latitude
        self.longitude = longitude
        self.aerialImageUrl = aerialImageUrl
        self.propertyDiagramUrl = propertyDiagramUrl
        self.irrigationMapStatus = irrigationMapStatus
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
    let priceBookItemId: String?
    let name: String
    let description: String?
    let quantity: Double
    let unitPrice: Double
    let unit: String
    let itemType: String?
    let sortOrder: Int
    let total: Double
    let optionId: String?

    enum CodingKeys: String, CodingKey {
        case id, priceBookItemId, name, description, quantity, unitPrice, unit, itemType, sortOrder, total, optionId
        case priceBookItem
        case price, amount, lineTotal, extendedPrice
    }

    private struct PriceBookRef: Decodable {
        let id: String?
        let type: String?
        let unit: String?
        let unitPrice: Double?

        enum CodingKeys: String, CodingKey {
            case id, type, unit, unitPrice, price
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            type = try container.decodeIfPresent(String.self, forKey: .type)
            unit = try container.decodeIfPresent(String.self, forKey: .unit)
            unitPrice = try container.decodeFlexibleDouble(forKey: .unitPrice)
                ?? (try container.decodeFlexibleDouble(forKey: .price))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let nested = try container.decodeIfPresent(PriceBookRef.self, forKey: .priceBookItem)
        priceBookItemId = try container.decodeIfPresent(String.self, forKey: .priceBookItemId) ?? nested?.id
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        quantity = try container.decodeFlexibleDouble(forKey: .quantity) ?? 0
        unitPrice = try container.decodeFlexibleDouble(forKey: .unitPrice)
            ?? (try container.decodeFlexibleDouble(forKey: .price))
            ?? nested?.unitPrice
            ?? 0
        let trimmedUnit = try container.decodeIfPresent(String.self, forKey: .unit)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        unit = (trimmedUnit?.isEmpty == false ? trimmedUnit : nil)
            ?? nested?.unit
            ?? "each"
        itemType = try container.decodeIfPresent(String.self, forKey: .itemType) ?? nested?.type
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        let decodedTotal = try container.decodeFlexibleDouble(forKey: .total)
            ?? (try container.decodeFlexibleDouble(forKey: .lineTotal))
            ?? (try container.decodeFlexibleDouble(forKey: .extendedPrice))
            ?? (try container.decodeFlexibleDouble(forKey: .amount))
        if let decodedTotal {
            total = decodedTotal
        } else {
            let qty = quantity
            let price = unitPrice
            total = qty > 0 && price > 0 ? qty * price : 0
        }
        optionId = try container.decodeIfPresent(String.self, forKey: .optionId)
    }

    var qtyPriceLabel: String {
        let qty = quantity.formatted(.number.precision(.fractionLength(0...2)))
        let price = unitPrice.formatted(.currency(code: "USD"))
        return "Qty \(qty) @\(price)/\(unit)"
    }

    /// Prefer server total; fall back to qty × unit price when total was persisted as 0.
    var displayTotal: Double {
        if total > 0 { return total }
        let computed = quantity * unitPrice
        return computed > 0 ? computed : total
    }

    var isMaterial: Bool {
        itemType?.uppercased() == "MATERIAL"
    }
}

struct DiscountDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let amount: Double
    let type: String
    let optionId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, label, amount, type, optionId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? (try container.decodeIfPresent(String.self, forKey: .label))
            ?? "Discount"
        amount = try container.decodeFlexibleDouble(forKey: .amount) ?? 0
        type = try container.decode(String.self, forKey: .type)
        optionId = try container.decodeIfPresent(String.self, forKey: .optionId)
    }
}

struct TimeEventDTO: Decodable, Identifiable {
    let id: String
    let type: String
    let occurredAt: String
    let user: NamedColor?

    enum CodingKeys: String, CodingKey {
        case id, type, occurredAt, user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        user = try container.decodeIfPresent(NamedColor.self, forKey: .user)
        if let text = try container.decodeIfPresent(String.self, forKey: .occurredAt) {
            occurredAt = text
        } else if let date = try container.decodeIfPresent(Date.self, forKey: .occurredAt) {
            occurredAt = APIDateFormatting.queryString(from: date)
        } else {
            occurredAt = ""
        }
    }
}

struct VisitNoteDTO: Decodable, Identifiable {
    let id: String
    let body: String
    let createdAt: String
    let author: NamedColor?

    enum CodingKeys: String, CodingKey {
        case id, body, createdAt, author
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        body = try container.decode(String.self, forKey: .body)
        author = try container.decodeIfPresent(NamedColor.self, forKey: .author)
        if let text = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = text
        } else if let date = try container.decodeIfPresent(Date.self, forKey: .createdAt) {
            createdAt = APIDateFormatting.queryString(from: date)
        } else {
            createdAt = ""
        }
    }
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
    let payments: [InvoicePaymentDTO]?

    enum CodingKeys: String, CodingKey {
        case id, invoiceNumber, status, total, paidAt, payments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        invoiceNumber = try container.decode(String.self, forKey: .invoiceNumber)
        status = try container.decode(String.self, forKey: .status)
        total = try container.decodeFlexibleDouble(forKey: .total) ?? 0
        payments = try container.decodeIfPresent([InvoicePaymentDTO].self, forKey: .payments)
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

struct ChecklistTemplateDTO: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let active: Bool?
    let requiredForCompletion: Bool?
}

struct ChecklistDTO: Decodable, Identifiable {
    let id: String
    let templateId: String?
    let name: String
    let items: [ChecklistItemDTO]
    let completedAt: String?
    let status: String?
    let requiredForCompletion: Bool?
    let progress: ChecklistProgressDTO?
}

struct ChecklistProgressDTO: Decodable {
    let requiredComplete: Int?
    let requiredTotal: Int?
    let itemCount: Int?
}

struct ChecklistItemDTO: Decodable, Identifiable {
    let id: String
    let label: String
    let type: String?
    let helpText: String?
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
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
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
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct PartsRunGetResponse: Decodable {
    let options: [PartsRunOptionDTO]?
    let message: String?
    let usedUserLocation: Bool?
}

struct PartsRunPostResponse: Decodable {
    let paused: Bool?
    let mapsUrl: String?
}

struct PartsRunOptionDTO: Decodable, Identifiable {
    var id: String { supplierId }
    let supplierId: String
    let name: String
    let address: String?
    let city: String?
    let phone: String?
    let driveMinutes: Int?
    let driveDistanceMiles: Double?
    let isOpenNow: Bool?
    let mapsUrl: String?

    enum CodingKeys: String, CodingKey {
        case supplierId, id, name, address, city, phone
        case driveMinutes, driveTimeMinutes, durationMinutes, driveSeconds, durationSeconds
        case driveDistanceMiles, distanceMiles
        case isOpenNow, openNow, mapsUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let sid = try container.decodeIfPresent(String.self, forKey: .supplierId) {
            supplierId = sid
        } else {
            supplierId = try container.decode(String.self, forKey: .id)
        }
        name = try container.decode(String.self, forKey: .name)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        mapsUrl = try container.decodeIfPresent(String.self, forKey: .mapsUrl)
        driveDistanceMiles = try container.decodeFlexibleDouble(forKey: .driveDistanceMiles)
            ?? (try container.decodeFlexibleDouble(forKey: .distanceMiles))
        isOpenNow = try container.decodeIfPresent(Bool.self, forKey: .isOpenNow)
            ?? container.decodeIfPresent(Bool.self, forKey: .openNow)

        let rawMinutes = Self.decodeInt(in: container, keys: [.driveMinutes, .driveTimeMinutes, .durationMinutes])
        let rawSeconds = Self.decodeInt(in: container, keys: [.driveSeconds, .durationSeconds])
        driveMinutes = Self.normalizedDriveMinutes(
            rawMinutes: rawMinutes,
            rawSeconds: rawSeconds,
            miles: driveDistanceMiles
        )
    }

    /// Prefer true minutes; convert seconds when the API (or a mislabeled field) sent seconds.
    private static func normalizedDriveMinutes(rawMinutes: Int?, rawSeconds: Int?, miles: Double?) -> Int? {
        if let rawSeconds {
            return max(1, Int((Double(rawSeconds) / 60.0).rounded()))
        }
        guard let rawMinutes else { return nil }
        // City driving is rarely > ~20 min/mile. Values like 1070 with ~8 mi are almost certainly seconds.
        if let miles, miles > 0.3, Double(rawMinutes) / miles > 25 {
            return max(1, Int((Double(rawMinutes) / 60.0).rounded()))
        }
        // Absolute sanity: > 12h for a "nearby supplier" list is almost always seconds.
        if rawMinutes > 12 * 60, miles == nil || (miles ?? 0) < 80 {
            return max(1, Int((Double(rawMinutes) / 60.0).rounded()))
        }
        return max(0, rawMinutes)
    }

    private static func decodeInt(in container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> Int? {
        for key in keys {
            guard container.contains(key) else { continue }
            if (try? container.decodeNil(forKey: key)) == true { continue }
            if let value = try? container.decode(Int.self, forKey: key) { return value }
            if let value = try? container.decode(Double.self, forKey: key) { return Int(value.rounded()) }
            if let text = try? container.decode(String.self, forKey: key),
               let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return Int(value.rounded())
            }
        }
        return nil
    }
}


struct CustomerPropertyDTO: Decodable, Identifiable {
    let id: String
    let customerId: String
    let name: String
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let isPrimary: Bool?
    let irrigationMapStatus: String?
    let irrigationZoneCount: Int?
    let shutoffValveLocation: String?
    let controllerLocation: String?

    var formattedAddress: String {
        [address, city, state, zip]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var propertySummary: PropertySummary {
        PropertySummary(
            id: id,
            name: name,
            address: address,
            city: city,
            state: state,
            zip: zip,
            irrigationMapStatus: irrigationMapStatus
        )
    }
}

struct MapsEmbedResponse: Decodable {
    let configured: Bool
    let placeEmbed: String?
    let streetEmbed: String?
    /// Optional still-image URLs from the CRM (preferred when present).
    let streetImage: String?
    let placeImage: String?
    let formattedAddress: String?

    enum CodingKeys: String, CodingKey {
        case configured, placeEmbed, streetEmbed, formattedAddress
        case streetImage, placeImage
        case streetViewImage, staticStreetView, staticMap
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configured = try container.decodeIfPresent(Bool.self, forKey: .configured) ?? false
        placeEmbed = try container.decodeIfPresent(String.self, forKey: .placeEmbed)
        streetEmbed = try container.decodeIfPresent(String.self, forKey: .streetEmbed)
        streetImage = try container.decodeIfPresent(String.self, forKey: .streetImage)
            ?? (try container.decodeIfPresent(String.self, forKey: .streetViewImage))
            ?? (try container.decodeIfPresent(String.self, forKey: .staticStreetView))
        placeImage = try container.decodeIfPresent(String.self, forKey: .placeImage)
            ?? (try container.decodeIfPresent(String.self, forKey: .staticMap))
        formattedAddress = try container.decodeIfPresent(String.self, forKey: .formattedAddress)
    }
}

struct VisitMaintenanceContextDTO: Decodable {
    let visitId: String
    let customerId: String?
    let propertyId: String?
    let linked: LinkedPlanVisitDTO?
    let enrollments: [EnrollmentSummaryDTO]?
    let assignablePlanVisits: [AssignablePlanVisitDTO]?
}

struct LinkedPlanVisitDTO: Decodable {
    let id: String
    let status: String
    let dueYear: Int
    let dueMonth: Int
    let visitTitle: String
    let season: String?
    let enrollment: EnrollmentRefDTO?
}

struct EnrollmentRefDTO: Decodable {
    let id: String?
    let status: String?
    let templateName: String?
    let propertyName: String?
}

struct EnrollmentSummaryDTO: Decodable, Identifiable {
    let id: String
    let status: String
    let templateName: String
    let propertyName: String
    let billingFrequency: String?
    let basePrice: Double?
    let nextBillingDate: String?
    let unscheduledVisitCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, status, templateName, propertyName, billingFrequency, basePrice, nextBillingDate, unscheduledVisitCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(String.self, forKey: .status)
        templateName = try container.decode(String.self, forKey: .templateName)
        propertyName = try container.decode(String.self, forKey: .propertyName)
        billingFrequency = try container.decodeIfPresent(String.self, forKey: .billingFrequency)
        basePrice = try container.decodeFlexibleDouble(forKey: .basePrice)
        nextBillingDate = try container.decodeIfPresent(String.self, forKey: .nextBillingDate)
        unscheduledVisitCount = try container.decodeIfPresent(Int.self, forKey: .unscheduledVisitCount)
    }

    var isActivePlan: Bool {
        ["ACTIVE", "PENDING_RENEWAL", "EXPIRING_SOON"].contains(status)
    }
}

struct AssignablePlanVisitDTO: Decodable, Identifiable {
    let id: String
    let visitTitle: String
    let dueYear: Int
    let dueMonth: Int
    let planName: String
    let propertyName: String
}

struct ConversationDTO: Decodable, Identifiable {
    let id: String
    let title: String?
    let participantPhone: String?
    let lastMessageAt: String?
    let customer: CustomerSummary?
    let previewMessages: [MessageDTO]?
    let unreadCount: Int?
    let hasUnread: Bool?

    var previewText: String? {
        previewMessages?.first?.body
    }

    var displayTitle: String {
        customer?.name ?? title ?? participantPhone ?? "Conversation"
    }

    /// Explicit unread only — never infer from "last message inbound" (that is unanswered, not unread).
    var appearsUnread: Bool {
        if let unreadCount { return unreadCount > 0 }
        if let hasUnread { return hasUnread }
        return false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        participantPhone = try container.decodeIfPresent(String.self, forKey: .participantPhone)
        customer = try container.decodeIfPresent(CustomerSummary.self, forKey: .customer)
        previewMessages = try container.decodeIfPresent([MessageDTO].self, forKey: .messages)
            ?? container.decodeIfPresent([MessageDTO].self, forKey: .previewMessages)
        if let text = try container.decodeIfPresent(String.self, forKey: .lastMessageAt) {
            lastMessageAt = text
        } else if let date = try container.decodeIfPresent(Date.self, forKey: .lastMessageAt) {
            lastMessageAt = APIDateFormatting.queryString(from: date)
        } else {
            lastMessageAt = nil
        }
        if let count = try container.decodeIfPresent(Int.self, forKey: .unreadCount) {
            unreadCount = max(0, count)
        } else if let flag = try container.decodeIfPresent(Bool.self, forKey: .unreadCount) {
            unreadCount = flag ? 1 : 0
        } else if let flag = try container.decodeIfPresent(Bool.self, forKey: .unread) {
            unreadCount = flag ? 1 : 0
        } else {
            unreadCount = nil
        }
        hasUnread = try container.decodeIfPresent(Bool.self, forKey: .hasUnread)
            ?? container.decodeIfPresent(Bool.self, forKey: .isUnread)
            ?? container.decodeIfPresent(Bool.self, forKey: .unread)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, participantPhone, lastMessageAt, customer, messages, previewMessages
        case unreadCount, hasUnread, isUnread, unread
    }
}

/// Inbox list endpoints may return a bare array or a wrapped object.
struct ConversationsListResponse: Decodable {
    let conversations: [ConversationDTO]

    init(conversations: [ConversationDTO]) {
        self.conversations = conversations
    }

    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([ConversationDTO].self) {
            conversations = array
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent([ConversationDTO].self, forKey: .conversations) {
            conversations = value
        } else if let value = try container.decodeIfPresent([ConversationDTO].self, forKey: .items) {
            conversations = value
        } else if let value = try container.decodeIfPresent([ConversationDTO].self, forKey: .data) {
            conversations = value
        } else if let value = try container.decodeIfPresent([ConversationDTO].self, forKey: .results) {
            conversations = value
        } else {
            conversations = []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case conversations, items, data, results
    }
}

struct MessagesResponse: Decodable {
    let conversation: ConversationDTO
    let messages: [MessageDTO]
}

struct MessageSenderDTO: Decodable {
    let id: String?
    let name: String?
    let email: String?
}

struct MessageMediaDTO: Decodable, Identifiable {
    let id: String
    let blobUrl: String
    let fileName: String?
    let mimeType: String
    let sizeBytes: Int?

    var isVideo: Bool { mimeType.lowercased().hasPrefix("video/") }
    var isImage: Bool { mimeType.lowercased().hasPrefix("image/") }
}

struct MessageDTO: Decodable, Identifiable {
    let id: String
    let body: String?
    let direction: String
    let sentAt: String?
    let createdAt: String?
    let sender: MessageSenderDTO?
    let media: [MessageMediaDTO]?
    let deliveryStatus: String?

    var displayDate: String { sentAt ?? createdAt ?? "" }
    var isOutbound: Bool { direction.uppercased() == "OUTBOUND" }

    /// Stable identity for inbox polling diffs (avoids ScrollView thrash on silent refresh).
    var scrollFingerprint: String {
        let mediaKey = media?.map { "\($0.id):\($0.blobUrl)" }.joined(separator: ",") ?? ""
        return [id, body ?? "", direction, deliveryStatus ?? "", mediaKey].joined(separator: "|")
    }

    enum CodingKeys: String, CodingKey {
        case id, body, direction, sentAt, createdAt, sender, media, deliveryStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        direction = try container.decodeIfPresent(String.self, forKey: .direction) ?? "INBOUND"
        sender = try container.decodeIfPresent(MessageSenderDTO.self, forKey: .sender)
        media = try container.decodeIfPresent([MessageMediaDTO].self, forKey: .media)
        deliveryStatus = try container.decodeIfPresent(String.self, forKey: .deliveryStatus)
        if let text = try container.decodeIfPresent(String.self, forKey: .sentAt) {
            sentAt = text
        } else if let date = try container.decodeIfPresent(Date.self, forKey: .sentAt) {
            sentAt = APIDateFormatting.queryString(from: date)
        } else {
            sentAt = nil
        }
        if let text = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = text
        } else if let date = try container.decodeIfPresent(Date.self, forKey: .createdAt) {
            createdAt = APIDateFormatting.queryString(from: date)
        } else {
            createdAt = nil
        }
    }
}

struct SendSmsResponse: Decodable {
    let conversation: ConversationDTO
    let message: MessageDTO
}

struct InboxMediaUploadResponse: Decodable {
    let blobUrl: String
    let publicUrl: String?
    let fileName: String
    let mimeType: String
    let sizeBytes: Int
}

struct InboxContactDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let phone: String?
    let email: String?
}

struct InboxEmployeeContactDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let phone: String?
    let email: String?
    let role: String?
}

struct InboxCustomerContactsResponse: Decodable {
    let customers: [InboxContactDTO]
}

struct InboxEmployeeContactsResponse: Decodable {
    let employees: [InboxEmployeeContactDTO]
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
    let balanceDue: Double?
}

struct VisitInvoiceResponse: Decodable {
    let invoice: InvoiceSummaryDTO
    let payLink: String?
    let balanceDue: Double?
    let emailSent: Bool?
    let smsSent: Bool?
}

struct PaymentConfirmResponse: Decodable {
    let confirmed: Bool?
    let invoiceId: String?
    let reason: String?
    let invoiceStatus: String?
}

struct CustomerDTO: Decodable, Identifiable {
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
    let doNotService: Bool?
    let leadSource: String?
    let tags: [String]?
    let createdAt: String?
    let updatedAt: String?
    let propertyCount: Int?
    let visitCount: Int?
    let estimateCount: Int?
    let invoiceCount: Int?

    var isArchived: Bool { status == "ARCHIVED" }

    var formattedAddress: String {
        [address, city, state, zip]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var subtitleLine: String {
        [phone, city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct CustomerUpdateBody: Encodable {
    var name: String?
    var phone: String?
    var email: String?
    var companyName: String?
    var address: String?
    var city: String?
    var state: String?
    var zip: String?
    var leadSource: String?
    var doNotService: Bool?
    var tags: [String]?
    var status: String?
}

struct CustomerCreateBody: Encodable {
    let name: String
    var phone: String?
    var email: String?
    var companyName: String?
    var address: String?
    var city: String?
    var state: String?
    var zip: String?
    var leadSource: String?
}

struct CustomerNoteDTO: Decodable, Identifiable {
    let id: String
    let body: String
    let createdAt: String
    let author: CustomerNoteAuthorDTO

    enum CodingKeys: String, CodingKey {
        case id, body, createdAt, author
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        body = try container.decode(String.self, forKey: .body)
        author = try container.decode(CustomerNoteAuthorDTO.self, forKey: .author)
        if let text = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = text
        } else if let date = try container.decodeIfPresent(Date.self, forKey: .createdAt) {
            createdAt = APIDateFormatting.queryString(from: date)
        } else {
            createdAt = ""
        }
    }
}

struct CustomerNoteAuthorDTO: Decodable {
    let id: String
    let name: String
    let photoUrl: String?
    let color: String?
}

struct CustomerLinkedEstimateDTO: Decodable, Identifiable {
    let id: String
    let status: String
    let total: Double
    let createdAt: String
    let visitId: String?
    let visitTitle: String?

    enum CodingKeys: String, CodingKey {
        case id, status, total, createdAt, visitId, visitTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(String.self, forKey: .status)
        total = try container.decodeFlexibleDouble(forKey: .total) ?? 0
        visitId = try container.decodeIfPresent(String.self, forKey: .visitId)
        visitTitle = try container.decodeIfPresent(String.self, forKey: .visitTitle)
        if let text = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = text
        } else if let date = try container.decodeIfPresent(Date.self, forKey: .createdAt) {
            createdAt = APIDateFormatting.queryString(from: date)
        } else {
            createdAt = ""
        }
    }
}

struct CustomerHistoryDTO: Decodable {
    let pastVisitCount: Int
    let visits: [CustomerHistoryVisitDTO]
    let estimatesWithoutVisit: [EstimateSummaryDTO]
    let estimatesLinkedToVisits: [CustomerLinkedEstimateDTO]?
    let invoices: [CustomerHistoryInvoiceDTO]?
}

struct CustomerHistoryInvoiceDTO: Decodable, Identifiable {
    let id: String
    let invoiceNumber: String
    let status: String
    let total: Double
    let createdAt: String
    let visitId: String?
    let visitTitle: String?

    enum CodingKeys: String, CodingKey {
        case id, invoiceNumber, status, total, createdAt, visitId, visitTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        invoiceNumber = try container.decode(String.self, forKey: .invoiceNumber)
        status = try container.decode(String.self, forKey: .status)
        total = try container.decodeFlexibleDouble(forKey: .total) ?? 0
        visitId = try container.decodeIfPresent(String.self, forKey: .visitId)
        visitTitle = try container.decodeIfPresent(String.self, forKey: .visitTitle)
        if let text = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = text
        } else if let date = try container.decodeIfPresent(Date.self, forKey: .createdAt) {
            createdAt = APIDateFormatting.queryString(from: date)
        } else {
            createdAt = ""
        }
    }
}

struct CustomerHistoryVisitDTO: Decodable, Identifiable {
    let id: String
    let title: String
    let startAt: String
    let status: String
    let assignedUserName: String?
}

extension String {
    /// User-facing label for visit status and time-event types.
    var visitDisplayLabel: String {
        if self == "EN_ROUTE" { return "On my way" }
        return replacingOccurrences(of: "_", with: " ")
    }
}
