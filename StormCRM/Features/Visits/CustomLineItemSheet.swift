import SwiftUI

struct CustomLineItemInput: Equatable {
    let name: String
    let description: String?
    let unitPrice: Double
    let quantity: Double
}

struct CreateLineItemBody: Encodable {
    let name: String
    let description: String?
    let unitPrice: Double
    let quantity: Double
}

struct CustomLineItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (CustomLineItemInput) async -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var unitPrice = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $name)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Price", text: $unitPrice)
                        .keyboardType(.decimalPad)
                } footer: {
                    Text("Quantity defaults to 1. You can change it after adding.")
                        .font(.caption)
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Custom line item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await save() }
                    }
                    .disabled(isSaving || !canSave)
                }
            }
            .overlay {
                if isSaving { ProgressView() }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !unitPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let price = Double(unitPrice.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "Enter a valid price"
            return
        }

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        error = nil
        defer { isSaving = false }

        await onSave(
            CustomLineItemInput(
                name: trimmedName,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                unitPrice: price,
                quantity: 1
            )
        )
        dismiss()
    }
}

struct LineItemAddButtons: View {
    let onPriceBook: () -> Void
    let onCustom: () -> Void
    var isDisabled: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Button("Price book", action: onPriceBook)
                .buttonStyle(StormSecondaryButtonStyle())
            Button("Custom", action: onCustom)
                .buttonStyle(StormSecondaryButtonStyle())
        }
        .disabled(isDisabled)
    }
}
