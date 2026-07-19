import Foundation

private struct PinnedPriceBookItemRecord: Codable {
    let id: String
    let name: String
    let description: String?
    let unitPrice: Double
    let unit: String?
    let type: String?
    let categoryId: String?
    let categoryName: String?
    let sku: String?

    init(item: PriceBookItemDTO) {
        id = item.id
        name = item.name
        description = item.description
        // Persist the sell price the UI shows — list payloads often leave unitPrice at 0
        // and put the real amount in priceBreakdown / lastCalculatedPrice.
        unitPrice = item.resolvedUnitPrice
        unit = item.unit
        type = item.type
        categoryId = item.categoryId
        categoryName = item.category?.name
        sku = item.sku
    }

    func toItem() -> PriceBookItemDTO {
        PriceBookItemDTO(
            id: id,
            name: name,
            description: description,
            unitPrice: unitPrice,
            unit: unit,
            type: type,
            categoryId: categoryId,
            category: categoryName.map {
                PriceBookCategorySummary(id: categoryId ?? "", name: $0, slug: nil, type: type)
            },
            sku: sku,
            sortOrder: nil
        )
    }
}

@MainActor
final class PriceBookPinStore: ObservableObject {
    @Published private(set) var items: [PriceBookItemDTO] = []

    private var storageKey = "priceBookPins.anonymous"

    func setUserId(_ userId: String?) {
        let key = "priceBookPins.\(userId ?? "anonymous")"
        guard key != storageKey else { return }
        storageKey = key
        load()
    }

    func isPinned(_ itemId: String) -> Bool {
        items.contains { $0.id == itemId }
    }

    func toggle(_ item: PriceBookItemDTO) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
        } else {
            items.insert(item, at: 0)
        }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PinnedPriceBookItemRecord].self, from: data)
        else {
            items = []
            return
        }
        items = decoded.map { $0.toItem() }
    }

    private func save() {
        let records = items.map(PinnedPriceBookItemRecord.init)
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
