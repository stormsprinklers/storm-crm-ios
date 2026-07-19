import SwiftUI

/// Compact line-items card with pencil → full builder (shared by visit + estimate).
struct LineItemsSummarySection: View {
    @EnvironmentObject private var env: AppEnvironment

    let owner: LineItemsOwner
    let items: [LineItemDTO]
    let discounts: [DiscountDTO]
    let subtotal: Double
    let discountTotal: Double
    let total: Double
    var canEdit: Bool = true
    var onUpdated: () async -> Void

    @State private var showBuilder = false

    private var serviceItems: [LineItemDTO] {
        items.filter { !$0.isMaterial }
    }

    private var materialItems: [LineItemDTO] {
        items.filter(\.isMaterial)
    }

    /// Only real discount records count — never infer a phantom discount from subtotal/total gaps.
    private var hasActiveDiscounts: Bool {
        !discounts.isEmpty
    }

    private var activeDiscountTotal: Double {
        guard hasActiveDiscounts else { return 0 }
        if discountTotal > 0 { return discountTotal }
        return visitDiscountTotal(subtotal: subtotal, discounts: discounts)
    }

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    StormSectionHeader(title: "Line items", systemImage: "list.bullet")
                    Spacer()
                    if canEdit {
                        Button {
                            showBuilder = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(StormTheme.sky)
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit line items")
                    }
                }

                if items.isEmpty && !hasActiveDiscounts {
                    Text(canEdit ? "Tap the pencil to add services, materials, and discounts." : "No line items.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(serviceItems) { item in
                        summaryRow(item)
                    }
                    ForEach(materialItems) { item in
                        summaryRow(item)
                    }
                    if hasActiveDiscounts {
                        ForEach(discounts) { discount in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(discount.name)
                                        .font(.subheadline.weight(.medium))
                                    Text(discount.type.uppercased() == "PERCENT"
                                          ? "\(discount.amount.formatted())% off"
                                          : discount.amount.formatted(.currency(code: "USD")))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }

                    Divider()
                    HStack {
                        Text("Subtotal")
                        Spacer()
                        Text(subtotal, format: .currency(code: "USD"))
                    }
                    .font(.subheadline)
                    if hasActiveDiscounts, activeDiscountTotal > 0 {
                        HStack {
                            Text("Discounts")
                            Spacer()
                            Text(-activeDiscountTotal, format: .currency(code: "USD"))
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Total").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(total, format: .currency(code: "USD"))
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .sheet(isPresented: $showBuilder) {
            NavigationStack {
                LineItemsBuilderView(owner: owner) {
                    await onUpdated()
                }
            }
            .environmentObject(env)
        }
    }

    private func summaryRow(_ item: LineItemDTO) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline.weight(.medium))
                Text(item.qtyPriceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.displayTotal, format: .currency(code: "USD"))
                .font(.subheadline.weight(.semibold))
        }
    }
}
