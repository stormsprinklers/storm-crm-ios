import SwiftUI

/// Optimistic qty per price-book item. UI updates immediately; network work is coalesced.
@MainActor
final class PriceBookLineItemQuantities: ObservableObject {
    @Published private(set) var quantities: [String: Double] = [:]
    @Published var error: String?

    private var lineItemByBookId: [String: String] = [:]
    private var debounceTasks: [String: Task<Void, Never>] = [:]
    private var flushChain: [String: Task<Void, Never>] = [:]

    private var api: APIClient?
    private let owner: LineItemsOwner
    private let optionId: String?

    init(owner: LineItemsOwner, optionId: String?) {
        self.owner = owner
        self.optionId = optionId
    }

    func attach(api: APIClient) {
        self.api = api
    }

    func quantity(forBookId id: String) -> Double {
        quantities[id] ?? 0
    }

    func loadExisting() async {
        guard let api else { return }
        do {
            let items = try await Self.fetchLineItems(api: api, owner: owner, optionId: optionId)
            var qty: [String: Double] = [:]
            var ids: [String: String] = [:]
            for item in items {
                guard let bookId = item.priceBookItemId, !bookId.isEmpty else { continue }
                qty[bookId, default: 0] += item.quantity
                ids[bookId] = item.id
            }
            quantities = qty
            lineItemByBookId = ids
            error = nil
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func increment(_ item: PriceBookItemDTO) {
        adjust(item, by: 1)
    }

    func decrement(_ item: PriceBookItemDTO) {
        adjust(item, by: -1)
    }

    private func adjust(_ item: PriceBookItemDTO, by delta: Double) {
        let current = quantities[item.id] ?? 0
        let next = max(0, current + delta)
        guard next != current else { return }
        quantities[item.id] = next
        error = nil

        debounceTasks[item.id]?.cancel()
        debounceTasks[item.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            await self?.enqueueFlush(item)
        }
    }

    private func enqueueFlush(_ item: PriceBookItemDTO) {
        let previous = flushChain[item.id]
        flushChain[item.id] = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await self?.flush(item)
        }
    }

    private func flush(_ item: PriceBookItemDTO) async {
        guard let api else { return }
        let desired = quantities[item.id] ?? 0
        let existingId = lineItemByBookId[item.id]

        do {
            if desired <= 0 {
                if let existingId {
                    try await api.delete(
                        path: owner.lineItemsPath,
                        query: [URLQueryItem(name: "lineItemId", value: existingId)]
                    )
                    lineItemByBookId[item.id] = nil
                }
                return
            }

            if let existingId {
                struct PatchBody: Encodable {
                    let lineItemId: String
                    let quantity: Double
                }
                let _: EmptyResponse = try await api.patch(
                    path: owner.lineItemsPath,
                    body: PatchBody(lineItemId: existingId, quantity: desired)
                )
                return
            }

            let createdId = try await Self.createLineItem(
                api: api,
                owner: owner,
                optionId: optionId,
                item: item,
                quantity: desired
            )
            lineItemByBookId[item.id] = createdId
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private static func createLineItem(
        api: APIClient,
        owner: LineItemsOwner,
        optionId: String?,
        item: PriceBookItemDTO,
        quantity: Double
    ) async throws -> String {
        struct Body: Encodable {
            let priceBookItemId: String
            let name: String
            let description: String?
            let unitPrice: Double
            let quantity: Double
            let unit: String?
            let optionId: String?

            enum CodingKeys: String, CodingKey {
                case priceBookItemId, name, description, unitPrice, price, quantity, unit, optionId
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(priceBookItemId, forKey: .priceBookItemId)
                try container.encode(name, forKey: .name)
                try container.encodeIfPresent(description, forKey: .description)
                try container.encode(unitPrice, forKey: .unitPrice)
                try container.encode(unitPrice, forKey: .price)
                try container.encode(quantity, forKey: .quantity)
                try container.encodeIfPresent(unit, forKey: .unit)
                try container.encodeIfPresent(optionId, forKey: .optionId)
            }
        }

        let body = Body(
            priceBookItemId: item.id,
            name: item.name,
            description: item.description,
            unitPrice: item.resolvedUnitPrice,
            quantity: quantity,
            unit: item.unit,
            optionId: optionId
        )

        let items: [LineItemDTO]
        switch owner {
        case .visit:
            let visit: VisitDetailDTO = try await api.post(path: owner.lineItemsPath, body: body)
            items = visit.lineItems ?? []
        case .estimate:
            let estimate: EstimateDetailDTO = try await api.post(path: owner.lineItemsPath, body: body)
            items = estimate.lineItems
        }

        let scoped: [LineItemDTO]
        if let optionId {
            scoped = items.filter { $0.optionId == optionId || $0.optionId == nil }
        } else {
            scoped = items
        }

        if let match = PriceBookLineItemAdding.matchingLineItem(in: scoped, for: item) {
            if PriceBookLineItemAdding.needsPriceCorrection(
                lineItem: match,
                expectedUnitPrice: item.resolvedUnitPrice
            ) {
                struct PatchBody: Encodable {
                    let lineItemId: String
                    let name: String
                    let quantity: Double
                    let unitPrice: Double
                    enum CodingKeys: String, CodingKey { case lineItemId, name, quantity, unitPrice, price }
                    func encode(to encoder: Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(lineItemId, forKey: .lineItemId)
                        try container.encode(name, forKey: .name)
                        try container.encode(quantity, forKey: .quantity)
                        try container.encode(unitPrice, forKey: .unitPrice)
                        try container.encode(unitPrice, forKey: .price)
                    }
                }
                let _: EmptyResponse = try await api.patch(
                    path: owner.lineItemsPath,
                    body: PatchBody(
                        lineItemId: match.id,
                        name: match.name,
                        quantity: quantity,
                        unitPrice: item.resolvedUnitPrice
                    )
                )
            }
            return match.id
        }

        throw APIError.server("Added item but could not read it back")
    }

    private static func fetchLineItems(
        api: APIClient,
        owner: LineItemsOwner,
        optionId: String?
    ) async throws -> [LineItemDTO] {
        switch owner {
        case .visit(let id):
            let visit: VisitDetailDTO = try await api.get(path: APIPath.visit(id))
            return visit.lineItems ?? []
        case .estimate(let id, let ownerOptionId):
            let estimate: EstimateDetailDTO = try await api.get(path: APIPath.estimate(id))
            let option = optionId ?? ownerOptionId
            guard let option else { return estimate.lineItems }
            return estimate.lineItems.filter { $0.optionId == option || $0.optionId == nil }
        }
    }
}

struct PriceBookQuantityStepper: View {
    let quantity: Double
    var minimum: Double = 0
    var onDecrement: () -> Void
    var onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onDecrement) {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(StormTheme.sky)
            }
            .buttonStyle(.borderless)
            .disabled(quantity <= minimum)
            .opacity(quantity <= minimum ? 0.35 : 1)
            .accessibilityLabel("Decrease quantity")

            Text(quantityLabel)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(StormTheme.navy)
                .frame(minWidth: 22)
                .accessibilityLabel("Quantity \(quantityLabel)")

            Button(action: onIncrement) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(StormTheme.sky)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Increase quantity")
        }
    }

    private var quantityLabel: String {
        if quantity == floor(quantity) {
            return String(Int(quantity))
        }
        return String(format: "%g", quantity)
    }
}
