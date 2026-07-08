import SwiftUI

struct VisitLineItemsEditSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let visitId: String
    let items: [LineItemDTO]
    let discounts: [DiscountDTO]
    var onUpdated: () async -> Void

    @State private var showPicker = false
    @State private var showCustomItem = false
    @State private var drafts = LineItemDraftFields()
    @State private var discountLabel = ""
    @State private var discountAmount = ""
    @State private var discountType = "FIXED"
    @State private var error: String?
    @State private var savingItemId: String?

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    StormSectionHeader(title: "Line items", systemImage: "list.bullet")
                    Spacer()
                    LineItemAddButtons(
                        onPriceBook: { showPicker = true },
                        onCustom: { showCustomItem = true }
                    )
                }

                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                if items.isEmpty {
                    Text("Add items from the price book or create a custom line item.")
                        .foregroundStyle(.secondary)
                } else {
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
                }

                Divider()
                discountEditor
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

    private var discountEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Discounts").font(.subheadline.bold())
            HStack {
                TextField("Label", text: $discountLabel)
                    .textFieldStyle(.roundedBorder)
                TextField("Amount", text: $discountAmount)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                Picker("Type", selection: $discountType) {
                    Text("$").tag("FIXED")
                    Text("%").tag("PERCENT")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 100)
                Button("Add") { Task { await addDiscount() } }
                    .buttonStyle(StormSecondaryButtonStyle())
                    .disabled(discountAmount.isEmpty)
            }
            ForEach(discounts) { discount in
                HStack {
                    Text("\(discount.name) — \(formatDiscount(discount))")
                        .font(.caption)
                    Spacer()
                    Button(role: .destructive) {
                        Task { await deleteDiscount(discount.id) }
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }


    private func formatDiscount(_ discount: DiscountDTO) -> String {
        if discount.type == "PERCENT" {
            return discount.amount.formatted(.number.precision(.fractionLength(0))) + "%"
        }
        return discount.amount.formatted(.currency(code: "USD"))
    }

    private func addCustomItem(_ input: CustomLineItemInput) async {
        do {
            let _: VisitDetailDTO = try await env.apiClient.post(
                path: APIPath.visitLineItems(visitId),
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

    private func addFromPriceBook(_ item: PriceBookItemDTO) async {
        let expectedUnitPrice = item.resolvedUnitPrice
        struct Body: Encodable {
            let priceBookItemId: String
            let name: String
            let description: String?
            let unitPrice: Double
            let quantity: Double
        }
        struct PatchBody: Encodable {
            let lineItemId: String
            let quantity: Double
            let unitPrice: Double
        }
        do {
            let visit: VisitDetailDTO = try await env.apiClient.post(
                path: APIPath.visitLineItems(visitId),
                body: Body(
                    priceBookItemId: item.id,
                    name: item.name,
                    description: item.description,
                    unitPrice: expectedUnitPrice,
                    quantity: 1
                )
            )
            if let added = PriceBookLineItemAdding.matchingLineItem(in: visit.lineItems ?? [], for: item),
               PriceBookLineItemAdding.needsPriceCorrection(lineItem: added, expectedUnitPrice: expectedUnitPrice) {
                let _: VisitDetailDTO = try await env.apiClient.patch(
                    path: APIPath.visitLineItems(visitId),
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
            let _: VisitDetailDTO = try await env.apiClient.patch(
                path: APIPath.visitLineItems(visitId),
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
        do {
            let _: VisitDetailDTO = try await env.apiClient.deleteReturningVisit(
                path: APIPath.visitLineItems(visitId),
                query: [URLQueryItem(name: "lineItemId", value: lineItemId)]
            )
            drafts.removeDrafts(for: lineItemId)
            await onUpdated()
        } catch {
            self.error = (error as? APIError)?.message
        }
    }

    private func addDiscount() async {
        guard let amount = Double(discountAmount) else { return }
        struct Body: Encodable {
            let label: String?
            let type: String
            let amount: Double
        }
        do {
            let _: VisitDetailDTO = try await env.apiClient.post(
                path: APIPath.visitDiscounts(visitId),
                body: Body(
                    label: discountLabel.isEmpty ? nil : discountLabel,
                    type: discountType,
                    amount: amount
                )
            )
            discountLabel = ""
            discountAmount = ""
            await onUpdated()
        } catch {
            self.error = (error as? APIError)?.message
        }
    }

    private func deleteDiscount(_ discountId: String) async {
        do {
            let _: VisitDetailDTO = try await env.apiClient.deleteReturningVisit(
                path: APIPath.visitDiscounts(visitId),
                query: [URLQueryItem(name: "discountId", value: discountId)]
            )
            await onUpdated()
        } catch {
            self.error = (error as? APIError)?.message
        }
    }
}
