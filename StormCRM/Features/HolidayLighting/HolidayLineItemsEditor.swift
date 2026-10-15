import SwiftUI

struct HLPricingFields: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var model: HolidayQuoteViewModel
    @State private var showCustom = false
    @State private var confirmReset = false
    private var adjustment: HLAdjustment { model.active.selections.adjustments[model.active.selections.pricingMode] ?? HLAdjustment() }
    var body: some View {
        Section("Line items") {
            if model.pricing == nil && adjustment.lineItems == nil {
                Button("Calculate line items") { Task { await model.save(api: env.apiClient) } }
            } else {
                ForEach(model.quoteLines) { line in
                    VStack(alignment: .leading, spacing: 6) {
                        if line.kind == "included" { Text("Included").font(.caption).foregroundStyle(.secondary) }
                        LineItemEditRow(
                            name: field(line, \.name), description: field(line, \.description),
                            quantity: numericField(line, quantity: true), unitPrice: numericField(line, quantity: false),
                            isSaving: model.busy,
                            onSave: { Task { await model.save(api: env.apiClient) } },
                            onDelete: { model.updateQuoteLines { $0.removeAll { $0.id == line.id } } },
                            currencyFormatted: true, priceReadOnly: line.kind == "included"
                        )
                    }
                }
                Button("Update prices from measurements") { confirmReset = true }
            }
            Button("Add line item", systemImage: "plus") { showCustom = true }.disabled(model.pricing == nil && adjustment.lineItems == nil)
        }
        Section("Discount") {
            TextField("Discount name", text: Binding(get: { adjustment.discountLabel ?? "" }, set: { value in change { $0.discountLabel = value } }))
            Picker("Type", selection: Binding(get: { adjustment.discountType ?? "fixed" }, set: { value in change { $0.discountType = value } })) { Text("Dollar amount").tag("fixed"); Text("Percent").tag("percent") }
            if adjustment.discountType == "percent" {
                TextField("Percent", value: Binding(get: { adjustment.discountAmount ?? 0 }, set: { value in change { $0.discountAmount = min(100, max(0, value)) } }), format: .number).keyboardType(.decimalPad)
            } else {
                TextField("Discount", value: Binding(get: { adjustment.discountAmount ?? 0 }, set: { value in change { $0.discountAmount = max(0, value) } }), format: .currency(code: "USD")).keyboardType(.decimalPad)
            }
        }
        .sheet(isPresented: $showCustom) {
            CustomLineItemSheet(currencyFormatted: true) { input in
                model.updateQuoteLines { $0.append(HLQuoteLine(id: UUID().uuidString, name: input.name, description: input.description ?? "", quantity: input.quantity, unitPrice: input.unitPrice, kind: "service")) }
            }
        }
        .alert("Replace edited line items?", isPresented: $confirmReset) {
            Button("Recalculate", role: .destructive) {
                change { $0.lineItems = nil; $0.price = nil; $0.partsPrice = nil; $0.laborPrice = nil }
                Task { await model.save(api: env.apiClient) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This replaces edited line item titles, descriptions and prices with the current measurements and company prices.") }
    }
    private func field(_ line: HLQuoteLine, _ path: WritableKeyPath<HLQuoteLine, String>) -> Binding<String> {
        Binding(get: { model.quoteLines.first { $0.id == line.id }?[keyPath: path] ?? line[keyPath: path] }, set: { value in
            model.updateQuoteLines { lines in if let index = lines.firstIndex(where: { $0.id == line.id }) { lines[index][keyPath: path] = value } }
        })
    }
    private func numericField(_ line: HLQuoteLine, quantity: Bool) -> Binding<String> {
        Binding(get: {
            let current = model.quoteLines.first { $0.id == line.id } ?? line
            return String(quantity ? current.quantity : current.unitPrice)
        }, set: { raw in
            guard let value = Double(raw), value.isFinite, value >= 0 else { return }
            model.updateQuoteLines { lines in
                if let index = lines.firstIndex(where: { $0.id == line.id }) {
                    if quantity { lines[index].quantity = min(10000, value) }
                    else { lines[index].unitPrice = line.kind == "included" ? 0 : min(9_999_999, value) }
                }
            }
        })
    }
    private func change(_ update: (inout HLAdjustment) -> Void) {
        model.edit(invalidatePreview: false) { option in
            var value = option.selections.adjustments[option.selections.pricingMode] ?? HLAdjustment()
            update(&value); option.selections.adjustments[option.selections.pricingMode] = value
        }
    }
}
