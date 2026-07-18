import Foundation

enum LineItemsOwner: Hashable {
    case visit(id: String)
    case estimate(id: String, optionId: String?)

    var lineItemsPath: String {
        switch self {
        case .visit(let id): return APIPath.visitLineItems(id)
        case .estimate(let id, _): return APIPath.estimateLineItems(id)
        }
    }

    var discountsPath: String {
        switch self {
        case .visit(let id): return APIPath.visitDiscounts(id)
        case .estimate(let id, _): return APIPath.estimateDiscounts(id)
        }
    }

    var reloadPath: String {
        switch self {
        case .visit(let id): return APIPath.visit(id)
        case .estimate(let id, _): return APIPath.estimate(id)
        }
    }
}

struct CatalogDiscountDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let code: String?
    let type: String
    let amount: Double
    let active: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, code, type, amount, active
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        type = try container.decode(String.self, forKey: .type)
        amount = try container.decodeFlexibleDouble(forKey: .amount) ?? 0
        active = try container.decodeIfPresent(Bool.self, forKey: .active)
    }

    var displayAmount: String {
        if type.uppercased() == "PERCENT" {
            return "\(amount.formatted(.number.precision(.fractionLength(0...2))))%"
        }
        return amount.formatted(.currency(code: "USD"))
    }
}

struct CatalogDiscountsResponse: Decodable {
    let discounts: [CatalogDiscountDTO]
}

struct FrequentItemsResponse: Decodable {
    let items: [PriceBookItemDTO]
}
