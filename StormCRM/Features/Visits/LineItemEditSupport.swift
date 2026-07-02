import SwiftUI

struct LineItemDraftFields {
    var names: [String: String] = [:]
    var descriptions: [String: String] = [:]
    var quantities: [String: String] = [:]
    var prices: [String: String] = [:]

    mutating func sync(from items: [LineItemDTO]) {
        for item in items {
            names[item.id] = item.name
            descriptions[item.id] = item.description ?? ""
            quantities[item.id] = formatEditableDecimal(item.quantity)
            prices[item.id] = formatEditableDecimal(item.unitPrice)
        }
    }

    mutating func removeDrafts(for lineItemId: String) {
        names.removeValue(forKey: lineItemId)
        descriptions.removeValue(forKey: lineItemId)
        quantities.removeValue(forKey: lineItemId)
        prices.removeValue(forKey: lineItemId)
    }

    func bindingName(for item: LineItemDTO) -> Binding<String> {
        Binding(
            get: { names[item.id] ?? item.name },
            set: { names[item.id] = $0 }
        )
    }

    func bindingDescription(for item: LineItemDTO) -> Binding<String> {
        Binding(
            get: { descriptions[item.id] ?? (item.description ?? "") },
            set: { descriptions[item.id] = $0 }
        )
    }

    func bindingQuantity(for item: LineItemDTO) -> Binding<String> {
        Binding(
            get: { quantities[item.id] ?? formatEditableDecimal(item.quantity) },
            set: { quantities[item.id] = $0 }
        )
    }

    func bindingPrice(for item: LineItemDTO) -> Binding<String> {
        Binding(
            get: { prices[item.id] ?? formatEditableDecimal(item.unitPrice) },
            set: { prices[item.id] = $0 }
        )
    }
}

func formatEditableDecimal(_ value: Double) -> String {
    if value == floor(value), value < 1_000_000 {
        return String(format: "%.0f", value)
    }
    return String(value)
}

struct LineItemEditRow: View {
    @Binding var name: String
    @Binding var description: String
    @Binding var quantity: String
    @Binding var unitPrice: String
    let isSaving: Bool
    let onSave: () -> Void
    let onDelete: () -> Void

    private var previewTotal: Double {
        let qty = Double(quantity.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let price = Double(unitPrice.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return qty * price
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                TextField("Name", text: $name)
                    .font(.subheadline.weight(.medium))
                    .textFieldStyle(.roundedBorder)
                Spacer(minLength: 8)
                Text(previewTotal, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.semibold))
            }

            TextField("Description (optional)", text: $description, axis: .vertical)
                .lineLimit(1...3)
                .font(.caption)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Qty").font(.caption2).foregroundStyle(.secondary)
                    TextField("Qty", text: $quantity)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unit price").font(.caption2).foregroundStyle(.secondary)
                    TextField("Price", text: $unitPrice)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                Button(action: onSave) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                }
                .disabled(isSaving)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .disabled(isSaving)
            }
        }
        .padding(10)
        .background(StormTheme.ice.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
