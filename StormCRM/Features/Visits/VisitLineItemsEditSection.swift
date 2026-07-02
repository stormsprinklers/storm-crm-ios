import SwiftUI

struct VisitLineItemsEditSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let visitId: String
    let items: [LineItemDTO]
    let discounts: [DiscountDTO]
    var onUpdated: () async -> Void

    @State private var showPicker = false
    @State private var draftQuantities: [String: String] = [:]
    @State private var draftPrices: [String: String] = [:]
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
                    Button("Add item") { showPicker = true }
                        .buttonStyle(StormSecondaryButtonStyle())
                }

                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                if items.isEmpty {
                    Text("No line items yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        lineItemRow(item)
                    }
                }

                Divider()
                discountEditor
            }
        }
        .onAppear { syncDrafts() }
        .onChange(of: items.map { "\($0.id):\($0.quantity):\($0.unitPrice)" }) { _, _ in syncDrafts() }
        .sheet(isPresented: $showPicker) {
            PriceBookPickerSheet { item in
                await addFromPriceBook(item)
            }
        }
    }

    @ViewBuilder
    private func lineItemRow(_ item: LineItemDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.subheadline.weight(.medium))
                    if let description = item.description, !description.isEmpty {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(item.total, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Qty").font(.caption2).foregroundStyle(.secondary)
                    TextField("Qty", text: bindingQuantity(for: item))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unit price").font(.caption2).foregroundStyle(.secondary)
                    TextField("Price", text: bindingPrice(for: item))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                Button {
                    Task { await saveItem(item) }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .disabled(savingItemId == item.id)

                Button(role: .destructive) {
                    Task { await deleteItem(item.id) }
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .padding(10)
        .background(StormTheme.ice.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private func bindingQuantity(for item: LineItemDTO) -> Binding<String> {
        Binding(
            get: { draftQuantities[item.id] ?? String(item.quantity) },
            set: { draftQuantities[item.id] = $0 }
        )
    }

    private func bindingPrice(for item: LineItemDTO) -> Binding<String> {
        Binding(
            get: { draftPrices[item.id] ?? String(item.unitPrice) },
            set: { draftPrices[item.id] = $0 }
        )
    }

    private func syncDrafts() {
        for item in items {
            draftQuantities[item.id] = formatEditableDecimal(item.quantity)
            draftPrices[item.id] = formatEditableDecimal(item.unitPrice)
        }
    }

    private func formatEditableDecimal(_ value: Double) -> String {
        if value == floor(value), value < 1_000_000 {
            return String(format: "%.0f", value)
        }
        return String(value)
    }

    private func formatDiscount(_ discount: DiscountDTO) -> String {
        if discount.type == "PERCENT" {
            return discount.amount.formatted(.number.precision(.fractionLength(0))) + "%"
        }
        return discount.amount.formatted(.currency(code: "USD"))
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
        guard let qty = Double(draftQuantities[item.id] ?? ""),
              let price = Double(draftPrices[item.id] ?? "") else {
            error = "Enter valid quantity and price"
            return
        }
        savingItemId = item.id
        defer { savingItemId = nil }
        struct Body: Encodable {
            let lineItemId: String
            let quantity: Double
            let unitPrice: Double
        }
        do {
            let _: VisitDetailDTO = try await env.apiClient.patch(
                path: APIPath.visitLineItems(visitId),
                body: Body(lineItemId: item.id, quantity: qty, unitPrice: price)
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
            draftQuantities.removeValue(forKey: lineItemId)
            draftPrices.removeValue(forKey: lineItemId)
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
