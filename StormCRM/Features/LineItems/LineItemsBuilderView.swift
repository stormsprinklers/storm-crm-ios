import SwiftUI

/// Full-screen line items editor: Services / Materials / Discounts (no deposits).
struct LineItemsBuilderView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let owner: LineItemsOwner
    var onUpdated: () async -> Void

    @State private var items: [LineItemDTO] = []
    @State private var discounts: [DiscountDTO] = []
    @State private var subtotal: Double = 0
    @State private var discountTotal: Double = 0
    @State private var total: Double = 0
    @State private var isLoading = true
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
                    Task {
                        await onUpdated()
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    Task {
                        await onUpdated()
                        dismiss()
                    }
                }
            }
        }
        .task { await reload() }
        .overlay {
            if isLoading { ProgressView() }
        }
        .sheet(item: $activeAddSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .service:
                    PriceBookBrowseAddView(owner: owner, itemType: "SERVICE", optionId: optionId) {
                        await reload()
                    }
                case .material:
                    PriceBookBrowseAddView(owner: owner, itemType: "MATERIAL", optionId: optionId) {
                        await reload()
                    }
                case .discount:
                    DiscountBrowseAddView(owner: owner, optionId: optionId) {
                        await reload()
                    }
                }
            }
            .environmentObject(env)
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
                            Text(item.qtyPriceLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(item.total, format: .currency(code: "USD"))
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

    private func reload() async {
        isLoading = items.isEmpty && discounts.isEmpty
        error = nil
        defer { isLoading = false }
        do {
            switch owner {
            case .visit(let id):
                let visit: VisitDetailDTO = try await env.apiClient.get(path: APIPath.visit(id))
                items = visit.lineItems ?? []
                discounts = visit.discounts ?? []
                let computedSub = items.reduce(0.0) { $0 + $1.total }
                subtotal = visit.subtotal ?? computedSub
                discountTotal = visitDiscountTotal(subtotal: subtotal, discounts: discounts)
                total = visit.total ?? max(0, subtotal - discountTotal)
                optionId = nil
            case .estimate(let id, let preferredOptionId):
                let estimate: EstimateDetailDTO = try await env.apiClient.get(path: APIPath.estimate(id))
                optionId = preferredOptionId ?? estimate.selectedOptionId ?? estimate.options.first?.id
                if let optionId {
                    items = estimate.lineItems.filter { $0.optionId == optionId || $0.optionId == nil }
                    discounts = estimate.discounts.filter { $0.optionId == optionId || $0.optionId == nil }
                    if let option = estimate.options.first(where: { $0.id == optionId }) {
                        subtotal = option.subtotal
                        discountTotal = option.discountTotal
                        total = option.total
                    } else {
                        subtotal = estimate.subtotal
                        discountTotal = estimate.discountTotal
                        total = estimate.total
                    }
                } else {
                    items = estimate.lineItems
                    discounts = estimate.discounts
                    subtotal = estimate.subtotal
                    discountTotal = estimate.discountTotal
                    total = estimate.total
                }
            }
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func deleteItem(_ id: String) async {
        do {
            try await env.apiClient.delete(
                path: owner.lineItemsPath,
                query: [URLQueryItem(name: "lineItemId", value: id)]
            )
            await reload()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func deleteDiscount(_ id: String) async {
        do {
            try await env.apiClient.delete(
                path: owner.discountsPath,
                query: [URLQueryItem(name: "discountId", value: id)]
            )
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
    @State private var quantity: String = ""
    @State private var unitPrice: String = ""
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Qty", text: $quantity)
                    .keyboardType(.decimalPad)
                TextField("Unit price", text: $unitPrice)
                    .keyboardType(.decimalPad)
                Text("Unit: \(item.unit)")
                    .foregroundStyle(.secondary)
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(isSaving)
            }
        }
        .onAppear {
            name = item.name
            quantity = formatEditableDecimal(item.quantity)
            unitPrice = formatEditableDecimal(item.unitPrice)
        }
    }

    private func save() async {
        guard let qty = Double(quantity.trimmingCharacters(in: .whitespacesAndNewlines)),
              let price = Double(unitPrice.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            error = "Enter a valid quantity and price"
            return
        }
        isSaving = true
        defer { isSaving = false }
        struct Body: Encodable {
            let lineItemId: String
            let name: String
            let quantity: Double
            let unitPrice: Double
        }
        do {
            let _: EmptyResponse = try await env.apiClient.patch(
                path: owner.lineItemsPath,
                body: Body(lineItemId: item.id, name: name, quantity: qty, unitPrice: price)
            )
            await onSaved()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
