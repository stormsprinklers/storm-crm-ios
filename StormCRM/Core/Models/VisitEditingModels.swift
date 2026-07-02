import Foundation

struct ScheduleFiltersResponse: Decodable {
    let employees: [ScheduleEmployeeDTO]?
}

struct ScheduleEmployeeDTO: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let color: String?
    let photoUrl: String?
}

extension ScheduleEmployeeDTO {
    var namedColor: NamedColor {
        NamedColor(id: id, name: name, color: color, photoUrl: photoUrl)
    }
}

struct PriceBookPriceBreakdownDTO: Decodable, Hashable {
    let total: Double?

    enum CodingKeys: String, CodingKey {
        case total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.decodeFlexibleDouble(forKey: .total)
    }
}

struct PriceBookItemDTO: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let unitPrice: Double
    let lastCalculatedPrice: Double?
    let pricingMode: String?
    let priceBreakdown: PriceBookPriceBreakdownDTO?
    let unit: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, unitPrice, lastCalculatedPrice, pricingMode, priceBreakdown, unit, type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        unitPrice = try container.decodeFlexibleDouble(forKey: .unitPrice) ?? 0
        lastCalculatedPrice = try container.decodeFlexibleDouble(forKey: .lastCalculatedPrice)
        pricingMode = try container.decodeIfPresent(String.self, forKey: .pricingMode)
        priceBreakdown = try container.decodeIfPresent(PriceBookPriceBreakdownDTO.self, forKey: .priceBreakdown)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        type = try container.decodeIfPresent(String.self, forKey: .type)
    }

    /// Best available sell price from list API (flat-rate, calculated, or manual).
    var resolvedUnitPrice: Double {
        if let breakdownTotal = priceBreakdown?.total, breakdownTotal > 0 {
            return breakdownTotal
        }
        if let lastCalculatedPrice, lastCalculatedPrice > 0 {
            return lastCalculatedPrice
        }
        return unitPrice
    }
}

enum PriceBookLineItemAdding {
    static func matchingLineItem(in items: [LineItemDTO], for priceBookItem: PriceBookItemDTO) -> LineItemDTO? {
        if let linked = items.first(where: { $0.priceBookItemId == priceBookItem.id }) {
            return linked
        }
        return items.last(where: { $0.name == priceBookItem.name })
    }

    static func needsPriceCorrection(lineItem: LineItemDTO, expectedUnitPrice: Double) -> Bool {
        expectedUnitPrice > 0 && lineItem.unitPrice == 0
    }
}

enum VisitDateEditing {
    static func date(from iso: String) -> Date {
        APIDateFormatting.parse(iso) ?? Date()
    }

    static func isoString(from date: Date) -> String {
        APIDateFormatting.queryString(from: date)
    }
}
