import Foundation

struct EstimateDetailDTO: Decodable, Identifiable {
    let id: String
    let status: String
    let expiresAt: String?
    let subtotal: Double
    let discountTotal: Double
    let total: Double
    let signedAt: String?
    let approvedAt: String?
    let createdAt: String
    let customer: EstimateCustomerDTO
    let property: EstimatePropertyDTO?
    let visit: EstimateVisitRefDTO?
    let lineItems: [LineItemDTO]

    enum CodingKeys: String, CodingKey {
        case id, status, expiresAt, subtotal, discountTotal, total
        case signedAt, approvedAt, createdAt, customer, property, visit, lineItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(String.self, forKey: .status)
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
        subtotal = try container.decodeFlexibleDouble(forKey: .subtotal) ?? 0
        discountTotal = try container.decodeFlexibleDouble(forKey: .discountTotal) ?? 0
        total = try container.decodeFlexibleDouble(forKey: .total) ?? 0
        signedAt = try container.decodeIfPresent(String.self, forKey: .signedAt)
        approvedAt = try container.decodeIfPresent(String.self, forKey: .approvedAt)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        customer = try container.decode(EstimateCustomerDTO.self, forKey: .customer)
        property = try container.decodeIfPresent(EstimatePropertyDTO.self, forKey: .property)
        visit = try container.decodeIfPresent(EstimateVisitRefDTO.self, forKey: .visit)
        lineItems = try container.decodeIfPresent([LineItemDTO].self, forKey: .lineItems) ?? []
    }

    var isApproved: Bool {
        status == "APPROVED" || signedAt != nil || approvedAt != nil
    }

    var canCopyToVisit: Bool {
        isApproved && status != "CONVERTED" && !lineItems.isEmpty
    }

    var statusLabel: String {
        status.replacingOccurrences(of: "_", with: " ")
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
    let visitId: String
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
