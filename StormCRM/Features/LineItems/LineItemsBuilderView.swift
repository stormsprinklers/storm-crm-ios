import SwiftUI

/// Full-screen line items editor: Services / Materials / Discounts (no deposits).
struct LineItemsBuilderView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let owner: LineItemsOwner
    var onUpdated: () async -> Void

    @State private var items: [LineItemDTO] = []
    @State private var discounts: [DiscountDTO] = []
    @State private var baselineItems: [LineItemDTO] = []
    @State private var baselineDiscounts: [DiscountDTO] = []
    @State private var didCaptureBaseline = false
    @State private var subtotal: Double = 0
    @State private var discountTotal: Double = 0
    @State private var total: Double = 0
    @State private var isLoading = true
    @State private var isReverting = false
    @State private var error: String?
    @State private var optionId: String?
    @State private var activeAddSheet: AddSheet?

    private enum AddSheet: Identifiable {
        case service
        case material
        case discount

        var id: String {
            switch self {
            case .service: return "service"
            case .material: return "material"
            case .discount: return "discount"
            }
        }
    }

    private var serviceItems: [LineItemDTO] {
        items.filter { !$0.isMaterial }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var materialItems: [LineItemDTO] {
        items.filter(\.isMaterial).sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            if let error {
                Section {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }

            sectionBlock(
                title: "Services",
                sectionItems: serviceItems,
                addLabel: "Add Services",
                browseType: .service
            )

            sectionBlock(
                title: "Materials",
                sectionItems: materialItems,
                addLabel: "Add Materials",
                browseType: .material
            )

            discountsSection

            Section {
                HStack {
                    Text("Subtotal")
                    Spacer()
                    Text(subtotal, format: .currency(code: "USD"))
                }
                if discountTotal > 0 {
                    HStack {
                        Text("Discounts")
                        Spacer()
                        Text(-discountTotal, format: .currency(code: "USD"))
                    }
                    .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Total").fontWeight(.semibold)
                    Spacer()
                    Text(total, format: .currency(code: "USD")).fontWeight(.semibold)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Line items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    Task { await cancelEdits() }
                }
                .disabled(isReverting)
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    Task { await confirmEdits() }
                }
                .disabled(isReverting)
            }
        }
        .task { await reload(captureBaseline: true) }
        .overlay {
            if isReverting {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView("Undoing changes…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            } else if isLoading {
                ProgressView()
            }
        }
        .sheet(item: $activeAddSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .service:
                    PriceBookBrowseAddView(
                        owner: owner,
                        itemType: "SERVICE",
                        optionId: optionId,
                        onAdded: { await reload() },
                        closePicker: { activeAddSheet = nil }
                    )
                case .material:
                    PriceBookBrowseAddView(
                        owner: owner,
                        itemType: "MATERIAL",
                        optionId: optionId,
                        onAdded: { await reload() },
                        closePicker: { activeAddSheet = nil }
                    )
                case .discount:
                    DiscountBrowseAddView(owner: owner, optionId: optionId) {
                        await reload()
                    }
                }
            }
            .environmentObject(env)
            .environmentObject(env.priceBookPins)
        }
    }

    @ViewBuilder
    private func sectionBlock(
        title: String,
        sectionItems: [LineItemDTO],
        addLabel: String,
        browseType: AddSheet
    ) -> some View {
        Section {
            ForEach(sectionItems) { item in
                NavigationLink {
                    LineItemDetailEditView(owner: owner, item: item) {
                        await reload()
                    }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            Task { await deleteItem(item.id) }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.body.weight(.medium))
                            if let description = item.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Text(item.qtyPriceLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(item.displayTotal, format: .currency(code: "USD"))
                    }
                }
            }
            .onMove { indices, newOffset in
                Task { await reorder(sectionItems: sectionItems, from: indices, to: newOffset) }
            }
            .onDelete { indexSet in
                let ids = indexSet.map { sectionItems[$0].id }
                Task {
                    for id in ids { await deleteItem(id) }
                }
            }

            Button {
                activeAddSheet = browseType
            } label: {
                Label {
                    Text(addLabel).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .buttonStyle(.borderless)
        } header: {
            Text(title)
        }
    }

    private var discountsSection: some View {
        Section {
            ForEach(discounts) { discount in
                HStack(spacing: 10) {
                    Button {
                        Task { await deleteDiscount(discount.id) }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(discount.name).font(.body.weight(.medium))
                        Text(
                            discount.type.uppercased() == "PERCENT"
                                ? "\(discount.amount.formatted())%"
                                : discount.amount.formatted(.currency(code: "USD"))
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .onDelete { indexSet in
                let ids = indexSet.map { discounts[$0].id }
                Task {
                    for id in ids { await deleteDiscount(id) }
                }
            }

            Button {
                activeAddSheet = .discount
            } label: {
                Label {
                    Text("Add Discounts").foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Discounts")
        }
    }

    private func confirmEdits() async {
        await onUpdated()
        dismiss()
    }

    private func cancelEdits() async {
        isReverting = true
        error = nil
        defer { isReverting = false }
        do {
            if sessionHasChanges {
                try await revertToBaseline()
            }
            await onUpdated()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private var sessionHasChanges: Bool {
        guard didCaptureBaseline else { return false }
        return Self.lineItemSignatures(items) != Self.lineItemSignatures(baselineItems)
            || Self.discountSignatures(discounts) != Self.discountSignatures(baselineDiscounts)
    }

    private static func lineItemSignatures(_ items: [LineItemDTO]) -> [String] {
        items
            .map {
                [
                    $0.id,
                    $0.name,
                    $0.description ?? "",
                    String($0.quantity),
                    String($0.unitPrice),
                    String($0.sortOrder),
                    $0.unit,
                ].joined(separator: "|")
            }
            .sorted()
    }

    private static func discountSignatures(_ discounts: [DiscountDTO]) -> [String] {
        discounts
            .map {
                [$0.id, $0.name, String($0.amount), $0.type.uppercased()].joined(separator: "|")
            }
            .sorted()
    }

    /// Restores the line items / discounts that existed when the builder opened.
    private func revertToBaseline() async throws {
        // Refresh from server so we diff against the true current state.
        try await reloadThrowing(captureBaseline: false)

        let baselineItemIds = Set(baselineItems.map(\.id))
        let currentItemIds = Set(items.map(\.id))
        let baselineDiscountIds = Set(baselineDiscounts.map(\.id))
        let currentDiscountIds = Set(discounts.map(\.id))

        for id in currentItemIds.subtracting(baselineItemIds) {
            try await deleteLineItemRequest(id)
        }
        for id in currentDiscountIds.subtracting(baselineDiscountIds) {
            try await deleteDiscountRequest(id)
        }

        let missingItems = baselineItems
            .filter { !currentItemIds.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
        for item in missingItems {
            try await recreateLineItem(item)
        }

        let missingDiscounts = baselineDiscounts.filter { !currentDiscountIds.contains($0.id) }
        for discount in missingDiscounts {
            try await recreateDiscount(discount)
        }

        try await reloadThrowing(captureBaseline: false)

        for baseline in baselineItems {
            guard let current = items.first(where: { $0.id == baseline.id }) else { continue }
            if current.name != baseline.name
                || current.description != baseline.description
                || current.quantity != baseline.quantity
                || current.unitPrice != baseline.unitPrice
                || current.sortOrder != baseline.sortOrder {
                try await patchLineItem(baseline)
            }
        }
    }

    private func deleteLineItemRequest(_ id: String) async throws {
        try await env.apiClient.delete(
            path: owner.lineItemsPath,
            query: [URLQueryItem(name: "lineItemId", value: id)]
        )
    }

    private func deleteDiscountRequest(_ id: String) async throws {
        try await env.apiClient.delete(
            path: owner.discountsPath,
            query: [URLQueryItem(name: "discountId", value: id)]
        )
    }

    private func recreateLineItem(_ item: LineItemDTO) async throws {
        struct Body: Encodable {
            let priceBookItemId: String?
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
                try container.encodeIfPresent(priceBookItemId, forKey: .priceBookItemId)
                try container.encode(name, forKey: .name)
                try container.encodeIfPresent(description, forKey: .description)
                try container.encode(unitPrice, forKey: .unitPrice)
                try container.encode(unitPrice, forKey: .price)
                try container.encode(quantity, forKey: .quantity)
                try container.encodeIfPresent(unit, forKey: .unit)
                try container.encodeIfPresent(optionId, forKey: .optionId)
            }
        }
        struct PatchBody: Encodable {
            let lineItemId: String
            let name: String
            let description: String?
            let quantity: Double
            let unitPrice: Double
            let sortOrder: Int
        }

        let _: EmptyResponse = try await env.apiClient.post(
            path: owner.lineItemsPath,
            body: Body(
                priceBookItemId: item.priceBookItemId,
                name: item.name,
                description: item.description,
                unitPrice: item.unitPrice,
                quantity: item.quantity,
                unit: item.unit,
                optionId: item.optionId ?? optionId
            )
        )

        // Re-apply qty/price/sortOrder — create endpoints often ignore some fields.
        let freshItems = try await fetchCurrentLineItems()
        guard let created = Self.matchRecreatedLineItem(item, in: freshItems) else { return }
        let _: EmptyResponse = try await env.apiClient.patch(
            path: owner.lineItemsPath,
            body: PatchBody(
                lineItemId: created.id,
                name: item.name,
                description: item.description,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                sortOrder: item.sortOrder
            )
        )
    }

    private static func matchRecreatedLineItem(_ item: LineItemDTO, in items: [LineItemDTO]) -> LineItemDTO? {
        if let bookId = item.priceBookItemId,
           let match = items.last(where: { $0.priceBookItemId == bookId && $0.name == item.name }) {
            return match
        }
        return items.last(where: { $0.name == item.name })
    }

    private func recreateDiscount(_ discount: DiscountDTO) async throws {
        struct Body: Encodable {
            let label: String
            let type: String
            let amount: Double
            let optionId: String?
        }
        let _: EmptyResponse = try await env.apiClient.post(
            path: owner.discountsPath,
            body: Body(
                label: discount.name,
                type: discount.type.uppercased() == "PERCENT" ? "PERCENT" : "FIXED",
                amount: discount.amount,
                optionId: discount.optionId ?? optionId
            )
        )
    }

    private func patchLineItem(_ item: LineItemDTO) async throws {
        struct Body: Encodable {
            let lineItemId: String
            let name: String
            let description: String?
            let quantity: Double
            let unitPrice: Double
            let sortOrder: Int
        }
        let _: EmptyResponse = try await env.apiClient.patch(
            path: owner.lineItemsPath,
            body: Body(
                lineItemId: item.id,
                name: item.name,
                description: item.description,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                sortOrder: item.sortOrder
            )
        )
    }

    private func fetchCurrentLineItems() async throws -> [LineItemDTO] {
        switch owner {
        case .visit(let id):
            let visit: VisitDetailDTO = try await env.apiClient.get(path: APIPath.visit(id))
            return visit.lineItems ?? []
        case .estimate(let id, let preferredOptionId):
            let estimate: EstimateDetailDTO = try await env.apiClient.get(path: APIPath.estimate(id))
            let optionId = preferredOptionId ?? estimate.selectedOptionId ?? estimate.options.first?.id
            if let optionId {
                return estimate.lineItems.filter { $0.optionId == optionId || $0.optionId == nil }
            }
            return estimate.lineItems
        }
    }

    private func reload(captureBaseline: Bool = false) async {
        do {
            try await reloadThrowing(captureBaseline: captureBaseline)
        } catch {
            // Error message already stored in `reloadThrowing`.
        }
    }

    private func reloadThrowing(captureBaseline: Bool) async throws {
        isLoading = items.isEmpty && discounts.isEmpty && !isReverting
        error = nil
        defer { isLoading = false }
        do {
            switch owner {
            case .visit(let id):
                let visit: VisitDetailDTO = try await env.apiClient.get(path: APIPath.visit(id))
                items = visit.lineItems ?? []
                discounts = visit.discounts ?? []
                // Prefer live line-item math; visit.subtotal/total often lag after add/delete.
                let computedSub = items.reduce(0.0) { $0 + $1.displayTotal }
                subtotal = computedSub
                discountTotal = visitDiscountTotal(subtotal: subtotal, discounts: discounts)
                total = max(0, subtotal - discountTotal)
                optionId = nil
            case .estimate(let id, let preferredOptionId):
                let estimate: EstimateDetailDTO = try await env.apiClient.get(path: APIPath.estimate(id))
                optionId = preferredOptionId ?? estimate.selectedOptionId ?? estimate.options.first?.id
                if let optionId {
                    items = estimate.lineItems.filter { $0.optionId == optionId || $0.optionId == nil }
                    discounts = estimate.discounts.filter { $0.optionId == optionId || $0.optionId == nil }
                } else {
                    items = estimate.lineItems
                    discounts = estimate.discounts
                }
                let computedSub = items.reduce(0.0) { $0 + $1.displayTotal }
                let option = optionId.flatMap { id in estimate.options.first(where: { $0.id == id }) }
                // Prefer server option totals when present; fall back to qty×price when API left totals at $0.
                subtotal = (option?.subtotal ?? estimate.subtotal).positiveOr(computedSub)
                discountTotal = discounts.isEmpty
                    ? 0
                    : (option?.discountTotal ?? estimate.discountTotal).positiveOr(
                        visitDiscountTotal(subtotal: subtotal, discounts: discounts)
                    )
                total = (option?.total ?? estimate.total).positiveOr(max(0, subtotal - discountTotal))
            }
            if captureBaseline || !didCaptureBaseline {
                baselineItems = items
                baselineDiscounts = discounts
                didCaptureBaseline = true
            }
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
            throw error
        }
    }

    private func deleteItem(_ id: String) async {
        do {
            try await deleteLineItemRequest(id)
            await reload()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func deleteDiscount(_ id: String) async {
        do {
            try await deleteDiscountRequest(id)
            await reload()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func reorder(sectionItems: [LineItemDTO], from indices: IndexSet, to newOffset: Int) async {
        var ordered = sectionItems
        ordered.move(fromOffsets: indices, toOffset: newOffset)
        for (index, item) in ordered.enumerated() {
            struct Body: Encodable {
                let lineItemId: String
                let sortOrder: Int
            }
            let _: EmptyResponse? = try? await env.apiClient.patch(
                path: owner.lineItemsPath,
                body: Body(lineItemId: item.id, sortOrder: index)
            )
        }
        await reload()
    }
}

struct LineItemDetailEditView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let owner: LineItemsOwner
    let item: LineItemDTO
    var onSaved: () async -> Void

    @State private var name: String = ""
    @State private var descriptionText: String = ""
    @State private var quantity: String = ""
    @State private var unitPrice: String = ""
    @State private var error: String?
    @State private var isSaving = false

    private var previewTotal: Double {
        let qty = Double(quantity.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let price = Double(unitPrice.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return qty * price
    }

    var body: some View {
        Form {
            Section("Item") {
                LabeledContent("Title") {
                    TextField("Title", text: $name)
                        .multilineTextAlignment(.trailing)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField(
                        "Shown on invoices and receipts",
                        text: $descriptionText,
                        axis: .vertical
                    )
                    .lineLimit(3...10)
                    Text("A short preview appears on the line item; the full text is included on invoices and receipts.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Pricing") {
                LabeledContent("Quantity") {
                    TextField("0", text: $quantity)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Unit price") {
                    TextField("0.00", text: $unitPrice)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Unit") {
                    Text(item.unit).foregroundStyle(.secondary)
                }
                LabeledContent("Line total") {
                    Text(previewTotal, format: .currency(code: "USD"))
                        .fontWeight(.semibold)
                }
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Edit line item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(isSaving)
            }
        }
        .onAppear {
            name = item.name
            descriptionText = item.description ?? ""
            quantity = formatEditableDecimal(item.quantity)
            unitPrice = formatEditableDecimal(item.unitPrice)
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            error = "Title is required"
            return
        }
        guard let qty = Double(quantity.trimmingCharacters(in: .whitespacesAndNewlines)),
              let price = Double(unitPrice.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            error = "Enter a valid quantity and unit price"
            return
        }
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        defer { isSaving = false }
        struct Body: Encodable {
            let lineItemId: String
            let name: String
            let description: String?
            let quantity: Double
            let unitPrice: Double
        }
        do {
            let _: EmptyResponse = try await env.apiClient.patch(
                path: owner.lineItemsPath,
                body: Body(
                    lineItemId: item.id,
                    name: trimmedName,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    quantity: qty,
                    unitPrice: price
                )
            )
            await onSaved()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
