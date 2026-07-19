import SwiftUI

/// Company discount catalog + custom % / $ discount entry.
struct DiscountBrowseAddView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let owner: LineItemsOwner
    var optionId: String?
    var onAdded: () async -> Void

    @State private var catalog: [CatalogDiscountDTO] = []
    @State private var label = ""
    @State private var amount = ""
    @State private var type = "FIXED"
    @State private var error: String?
    @State private var isLoading = false
    @State private var isSaving = false

    var body: some View {
        Form {
            if let error {
                Section { Text(error).foregroundStyle(.red).font(.caption) }
            }

            Section("Company discounts") {
                if catalog.isEmpty {
                    Text("No catalog discounts yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(catalog.filter { $0.active != false }) { discount in
                        Button {
                            Task { await applyCatalog(discount) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(discount.name)
                                        .foregroundStyle(.primary)
                                    Text(discount.displayAmount)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

            Section("Custom discount") {
                TextField("Title", text: $label)
                Picker("Type", selection: $type) {
                    Text("$ Fixed").tag("FIXED")
                    Text("% Percent").tag("PERCENT")
                }
                .pickerStyle(.segmented)
                TextField(type == "PERCENT" ? "Percent" : "Amount", text: $amount)
                    .keyboardType(.decimalPad)
                Button {
                    Task { await applyCustom() }
                } label: {
                    Text(isSaving ? "Adding…" : "Add custom discount")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("Discounts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
            }
        }
        .task { await loadCatalog() }
        .overlay { if isLoading { ProgressView() } }
    }

    private func loadCatalog() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: CatalogDiscountsResponse = try await env.apiClient.get(
                path: APIPath.priceBookDiscounts
            )
            catalog = response.discounts
        } catch {
            // Catalog is optional — custom entry still works
            catalog = []
        }
    }

    private func applyCatalog(_ discount: CatalogDiscountDTO) async {
        await postDiscount(
            label: discount.name,
            type: discount.type.uppercased() == "PERCENT" ? "PERCENT" : "FIXED",
            amount: discount.amount
        )
    }

    private func applyCustom() async {
        guard let value = Double(amount.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            error = "Enter a valid amount"
            return
        }
        let title = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            error = "Enter a title for this discount"
            return
        }
        await postDiscount(label: title, type: type, amount: value)
    }

    private func postDiscount(label: String, type: String, amount: Double) async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        struct Body: Encodable {
            let label: String
            let type: String
            let amount: Double
            let optionId: String?
        }
        do {
            let _: EmptyResponse = try await env.apiClient.post(
                path: owner.discountsPath,
                body: Body(label: label, type: type, amount: amount, optionId: optionId)
            )
            await onAdded()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
