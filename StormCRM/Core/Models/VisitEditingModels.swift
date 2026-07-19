import Foundation

struct ScheduleFiltersResponse: Decodable {
    let employees: [ScheduleEmployeeDTO]?
    let serviceAreas: [ScheduleServiceAreaDTO]?
}

struct ScheduleServiceAreaDTO: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let color: String?
    let slug: String?
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

struct PriceBookCategorySummary: Decodable, Hashable {
    let id: String
    let name: String
    let slug: String?
    let type: String?
}

struct PriceBookCategoryDTO: Decodable, Identifiable, Hashable {
    let id: String
    let type: String
    let name: String
    let slug: String?
    let parentId: String?
    let sortOrder: Int?
    let itemCount: Int?
    let childCount: Int?
    let children: [PriceBookCategoryDTO]?

    enum CodingKeys: String, CodingKey {
        case id, type, name, slug, parentId, sortOrder, children
        case count = "_count"
    }

    private struct Count: Decodable {
        let items: Int?
        let children: Int?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        name = try container.decode(String.self, forKey: .name)
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
        children = try container.decodeIfPresent([PriceBookCategoryDTO].self, forKey: .children)
        if let count = try container.decodeIfPresent(Count.self, forKey: .count) {
            itemCount = count.items
            childCount = count.children
        } else {
            itemCount = nil
            childCount = nil
        }
    }
}

struct PriceBookCategoryDetailDTO: Decodable {
    let id: String
    let type: String
    let name: String
    let parent: PriceBookCategorySummary?
    let children: [PriceBookCategoryDTO]?
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
    let categoryId: String?
    let category: PriceBookCategorySummary?
    let sku: String?
    let sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, description, unitPrice, lastCalculatedPrice, pricingMode, priceBreakdown
        case unit, type, categoryId, category, sku, sortOrder
        case price, defaultPrice, sellPrice, amount
    }

    init(
        id: String,
        name: String,
        description: String?,
        unitPrice: Double,
        lastCalculatedPrice: Double? = nil,
        pricingMode: String? = nil,
        priceBreakdown: PriceBookPriceBreakdownDTO? = nil,
        unit: String? = nil,
        type: String? = nil,
        categoryId: String? = nil,
        category: PriceBookCategorySummary? = nil,
        sku: String? = nil,
        sortOrder: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.unitPrice = unitPrice
        self.lastCalculatedPrice = lastCalculatedPrice
        self.pricingMode = pricingMode
        self.priceBreakdown = priceBreakdown
        self.unit = unit
        self.type = type
        self.categoryId = categoryId
        self.category = category
        self.sku = sku
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        unitPrice = try container.decodeFlexibleDouble(forKey: .unitPrice)
            ?? (try container.decodeFlexibleDouble(forKey: .price))
            ?? (try container.decodeFlexibleDouble(forKey: .defaultPrice))
            ?? (try container.decodeFlexibleDouble(forKey: .sellPrice))
            ?? (try container.decodeFlexibleDouble(forKey: .amount))
            ?? 0
        lastCalculatedPrice = try container.decodeFlexibleDouble(forKey: .lastCalculatedPrice)
        pricingMode = try container.decodeIfPresent(String.self, forKey: .pricingMode)
        priceBreakdown = try container.decodeIfPresent(PriceBookPriceBreakdownDTO.self, forKey: .priceBreakdown)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        categoryId = try container.decodeIfPresent(String.self, forKey: .categoryId)
        category = try container.decodeIfPresent(PriceBookCategorySummary.self, forKey: .category)
        sku = try container.decodeIfPresent(String.self, forKey: .sku)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
    }

    var displayCategoryName: String? {
        category?.name
    }

    var typeLabel: String {
        type == "MATERIAL" ? "Material" : "Service"
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
        expectedUnitPrice > 0 && (lineItem.unitPrice == 0 || lineItem.total == 0)
    }

    /// Adds a price-book item, then patches unit price when the API persists $0.
    static func add(
        api: APIClient,
        owner: LineItemsOwner,
        item: PriceBookItemDTO,
        optionId: String?
    ) async throws {
        let expectedUnitPrice = item.resolvedUnitPrice
        struct Body: Encodable {
            let priceBookItemId: String
            let name: String
            let description: String?
            let unitPrice: Double
            let quantity: Double
            let unit: String?
            let optionId: String?

            enum CodingKeys: String, CodingKey {
                case priceBookItemId, name, description, unitPrice, quantity, unit, optionId
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(priceBookItemId, forKey: .priceBookItemId)
                try container.encode(name, forKey: .name)
                try container.encodeIfPresent(description, forKey: .description)
                try container.encode(unitPrice, forKey: .unitPrice)
                try container.encode(quantity, forKey: .quantity)
                try container.encodeIfPresent(unit, forKey: .unit)
                try container.encodeIfPresent(optionId, forKey: .optionId)
            }
        }
        struct PatchBody: Encodable {
            let lineItemId: String
            let quantity: Double
            let unitPrice: Double
        }

        let _: EmptyResponse = try await api.post(
            path: owner.lineItemsPath,
            body: Body(
                priceBookItemId: item.id,
                name: item.name,
                description: item.description,
                unitPrice: expectedUnitPrice,
                quantity: 1,
                unit: item.unit,
                optionId: optionId
            )
        )

        guard expectedUnitPrice > 0 else { return }

        let lineItems = try await fetchLineItems(api: api, owner: owner)
        guard let added = matchingLineItem(in: lineItems, for: item),
              needsPriceCorrection(lineItem: added, expectedUnitPrice: expectedUnitPrice)
        else { return }

        let _: EmptyResponse = try await api.patch(
            path: owner.lineItemsPath,
            body: PatchBody(
                lineItemId: added.id,
                quantity: added.quantity > 0 ? added.quantity : 1,
                unitPrice: expectedUnitPrice
            )
        )
    }

    private static func fetchLineItems(api: APIClient, owner: LineItemsOwner) async throws -> [LineItemDTO] {
        switch owner {
        case .visit(let id):
            let visit: VisitDetailDTO = try await api.get(path: APIPath.visit(id))
            return visit.lineItems ?? []
        case .estimate(let id, let optionId):
            let estimate: EstimateDetailDTO = try await api.get(path: APIPath.estimate(id))
            if let optionId {
                return estimate.lineItems.filter { $0.optionId == optionId || $0.optionId == nil }
            }
            return estimate.lineItems
        }
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
