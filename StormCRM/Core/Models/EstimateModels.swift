import Foundation

struct EstimateOptionDTO: Decodable, Identifiable {
    let id: String
    let letter: String?
    let label: String
    let sortOrder: Int
    let subtotal: Double
    let discountTotal: Double
    let total: Double
    let displayNumber: String

    enum CodingKeys: String, CodingKey {
        case id, letter, label, sortOrder, subtotal, discountTotal, total, displayNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        letter = try container.decodeIfPresent(String.self, forKey: .letter)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? "Option"
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        subtotal = try container.decodeFlexibleDouble(forKey: .subtotal) ?? 0
        discountTotal = try container.decodeFlexibleDouble(forKey: .discountTotal) ?? 0
        total = try container.decodeFlexibleDouble(forKey: .total) ?? 0
        displayNumber = try container.decodeIfPresent(String.self, forKey: .displayNumber) ?? label
    }
}

struct EstimateDetailDTO: Decodable, Identifiable {
    let id: String
    let estimateNumber: String?
    let status: String
    let expiresAt: String?
    let selectedOptionId: String?
    let subtotal: Double
    let discountTotal: Double
    let total: Double
    let signedAt: String?
    let approvedAt: String?
    let signatureBlobUrl: String?
    let createdAt: String
    let customer: EstimateCustomerDTO
    let property: EstimatePropertyDTO?
    let visit: EstimateVisitRefDTO?
    let options: [EstimateOptionDTO]
    let lineItems: [LineItemDTO]
    let discounts: [DiscountDTO]

    enum CodingKeys: String, CodingKey {
        case id, estimateNumber, status, expiresAt, selectedOptionId
        case subtotal, discountTotal, total
        case signedAt, approvedAt, signatureBlobUrl, createdAt, customer, property, visit
        case options, lineItems, discounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        estimateNumber = try container.decodeIfPresent(String.self, forKey: .estimateNumber)
        status = try container.decode(String.self, forKey: .status)
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
        selectedOptionId = try container.decodeIfPresent(String.self, forKey: .selectedOptionId)
        subtotal = try container.decodeFlexibleDouble(forKey: .subtotal) ?? 0
        discountTotal = try container.decodeFlexibleDouble(forKey: .discountTotal) ?? 0
        total = try container.decodeFlexibleDouble(forKey: .total) ?? 0
        signedAt = try container.decodeIfPresent(String.self, forKey: .signedAt)
        approvedAt = try container.decodeIfPresent(String.self, forKey: .approvedAt)
        signatureBlobUrl = try container.decodeIfPresent(String.self, forKey: .signatureBlobUrl)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        customer = try container.decode(EstimateCustomerDTO.self, forKey: .customer)
        property = try container.decodeIfPresent(EstimatePropertyDTO.self, forKey: .property)
        visit = try container.decodeIfPresent(EstimateVisitRefDTO.self, forKey: .visit)
        options = try container.decodeIfPresent([EstimateOptionDTO].self, forKey: .options) ?? []
        lineItems = try container.decodeIfPresent([LineItemDTO].self, forKey: .lineItems) ?? []
        discounts = try container.decodeIfPresent([DiscountDTO].self, forKey: .discounts) ?? []
    }

    var isApproved: Bool {
        status == "APPROVED" || status == "CONVERTED" || signedAt != nil || approvedAt != nil
    }

    var canCopyToVisit: Bool {
        isApproved && status != "CONVERTED" && !lineItems.isEmpty
    }

    var statusLabel: String {
        status.replacingOccurrences(of: "_", with: " ")
    }

    var displayTitle: String {
        if let selected = options.first(where: { $0.id == selectedOptionId }) {
            return selected.displayNumber
        }
        if let first = options.first {
            return first.displayNumber
        }
        return estimateNumber ?? "Estimate"
    }
}

struct EstimateCustomerDTO: Decodable {
    let id: String
    let name: String
    let phone: String?
    let email: String?
}

struct EstimatePropertyDTO: Decodable {
    let id: String
    let name: String
    let address: String?
    let city: String?
    let state: String?
    let zip: String?

    enum CodingKeys: String, CodingKey {
        case id, name, address, city, state, zip
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        zip = try container.decodeIfPresent(String.self, forKey: .zip)
    }

    var formattedAddress: String? {
        AppleMapsURL.formattedAddress(street: address, city: city, state: state, zip: zip)
            ?? name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForMaps
    }
}

private extension String {
    var nilIfBlankForMaps: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct EstimateVisitRefDTO: Decodable {
    let id: String
    let title: String
    let startAt: String
}

struct EstimateCopyResponse: Decodable {
    let visitId: String
    let estimateId: String
}

struct CreateEstimateBody: Encodable {
    let customerId: String
    let propertyId: String?
    /// Optional: estimates created from the customer profile have no originating visit.
    let visitId: String?
}

struct EstimateStatusBody: Encodable {
    let status: String
}

struct AddEstimateLineItemBody: Encodable {
    let priceBookItemId: String
    let quantity: Double
    let unitPrice: Double
}

struct EstimateCopyBody: Encodable {
    let target: String
    let visitId: String?
    let schedule: EstimateCopyScheduleBody?
}

struct EstimateCopyScheduleBody: Encodable {
    let title: String
    let startAt: String
    let endAt: String
    let division: String
    let zip: String?
    let serviceAreaId: String?
    let assignedUserId: String?
    let address: String?
    let city: String?
    let state: String?
}
