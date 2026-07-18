import SwiftUI

struct EstimateLineItemsEditSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let estimateId: String
    let items: [LineItemDTO]
    let canEdit: Bool
    var onUpdated: () async -> Void

    @State private var showPicker = false
    @State private var showCustomItem = false
    @State private var drafts = LineItemDraftFields()
    @State private var error: String?
    @State private var savingItemId: String?
    @State private var isSaving = false

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    StormSectionHeader(title: "Line items", systemImage: "list.bullet")
                    Spacer()
                    if canEdit {
                        LineItemAddButtons(
                            onPriceBook: { showPicker = true },
                            onCustom: { showCustomItem = true },
                            isDisabled: isSaving
                        )
                    }
                }

                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                if items.isEmpty {
                    Text("Add items from the price book or create a custom line item.")
                        .foregroundStyle(.secondary)
                } else if canEdit {
                    ForEach(items) { item in
                        LineItemEditRow(
                            name: $drafts.bindingName(for: item),
                            description: $drafts.bindingDescription(for: item),
                            quantity: $drafts.bindingQuantity(for: item),
                            unitPrice: $drafts.bindingPrice(for: item),
                            isSaving: savingItemId == item.id,
                            onSave: { Task { await saveItem(item) } },
                            onDelete: { Task { await deleteItem(item.id) } }
                        )
                    }
                } else {
                    ForEach(items) { item in
                        readOnlyRow(item)
                        if item.id != items.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .onAppear { drafts.sync(from: items) }
        .onChange(of: items.map { "\($0.id):\($0.name):\($0.description ?? ""):\($0.quantity):\($0.unitPrice)" }) { _, _ in
            drafts.sync(from: items)
        }
        .sheet(isPresented: $showPicker) {
            PriceBookPickerSheet { item in
                await addFromPriceBook(item)
            }
        }
        .sheet(isPresented: $showCustomItem) {
            CustomLineItemSheet { input in
                await addCustomItem(input)
            }
        }
    }

    @ViewBuilder
    private func readOnlyRow(_ item: LineItemDTO) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline.weight(.medium))
                if let description = item.description, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
                Text(item.qtyPriceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.total, format: .currency(code: "USD"))
                .font(.subheadline.weight(.semibold))
        }
    }

    private func addFromPriceBook(_ item: PriceBookItemDTO) async {
        let expectedUnitPrice = item.resolvedUnitPrice
        isSaving = true
        error = nil
        defer { isSaving = false }
        struct Body: Encodable {
            let priceBookItemId: String
            let name: String
            let description: String?
            let unitPrice: Double
            let quantity: Double
            let unit: String?
        }
        struct PatchBody: Encodable {
            let lineItemId: String
            let quantity: Double
            let unitPrice: Double
        }
        do {
            var updated: EstimateDetailDTO = try await env.apiClient.post(
                path: APIPath.estimateLineItems(estimateId),
                body: Body(
                    priceBookItemId: item.id,
                    name: item.name,
                    description: item.description,
                    unitPrice: expectedUnitPrice,
                    quantity: 1,
                    unit: item.unit
                )
            )
            if let added = PriceBookLineItemAdding.matchingLineItem(in: updated.lineItems, for: item),
               PriceBookLineItemAdding.needsPriceCorrection(lineItem: added, expectedUnitPrice: expectedUnitPrice) {
                updated = try await env.apiClient.patch(
                    path: APIPath.estimateLineItems(estimateId),
                    body: PatchBody(
                        lineItemId: added.id,
                        quantity: added.quantity,
                        unitPrice: expectedUnitPrice
                    )
                )
            }
            await onUpdated()
        } catch {
            self.error = (error as? APIError)?.message
        }
    }

    private func addCustomItem(_ input: CustomLineItemInput) async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let _: EstimateDetailDTO = try await env.apiClient.post(
                path: APIPath.estimateLineItems(estimateId),
                body: CreateLineItemBody(
                    name: input.name,
                    description: input.description,
                    unitPrice: input.unitPrice,
                    quantity: input.quantity
                )
            )
            await onUpdated()
        } catch {
            self.error = (error as? APIError)?.message
        }
    }

    private func saveItem(_ item: LineItemDTO) async {
        let trimmedName = (drafts.names[item.id] ?? item.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            error = "Name is required"
            return
        }
        guard let qty = Double(drafts.quantities[item.id] ?? ""),
              let price = Double(drafts.prices[item.id] ?? "") else {
            error = "Enter valid quantity and price"
            return
        }

        let description = drafts.descriptions[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        savingItemId = item.id
        defer { savingItemId = nil }
        struct Body: Encodable {
            let lineItemId: String
            let name: String
            let description: String?
            let quantity: Double
            let unitPrice: Double
        }
        do {
            let _: EstimateDetailDTO = try await env.apiClient.patch(
                path: APIPath.estimateLineItems(estimateId),
                body: Body(
                    lineItemId: item.id,
                    name: trimmedName,
                    description: description?.isEmpty == true ? nil : description,
                    quantity: qty,
                    unitPrice: price
                )
            )
            await onUpdated()
        } catch {
            self.error = (error as? APIError)?.message
        }
    }

    private func deleteItem(_ lineItemId: String) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await env.apiClient.delete(
                path: APIPath.estimateLineItems(estimateId),
                query: [URLQueryItem(name: "lineItemId", value: lineItemId)]
            )
            drafts.removeDrafts(for: lineItemId)
            await onUpdated()
        } catch {
            self.error = (error as? APIError)?.message
        }
    }
}
