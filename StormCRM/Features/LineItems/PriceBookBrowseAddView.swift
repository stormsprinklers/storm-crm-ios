import SwiftUI

/// Browse / search / favorites / frequently-used price book picker for adding line items.
struct PriceBookBrowseAddView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let owner: LineItemsOwner
    let itemType: String
    var optionId: String?
    var onAdded: () async -> Void

    @State private var tab: BrowseTab = .all
    @State private var search = ""
    @State private var categories: [PriceBookCategoryDTO] = []
    @State private var frequent: [PriceBookItemDTO] = []
    @State private var searchResults: [PriceBookItemDTO] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var showCreate = false

    private enum BrowseTab: String, CaseIterable, Identifiable {
        case all, favorites
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return itemType == "MATERIAL" ? "All materials" : "All services"
            case .favorites: return "Favorites"
            }
        }
    }

    private var title: String {
        itemType == "MATERIAL" ? "Materials" : "Services"
    }

    private var favorites: [PriceBookItemDTO] {
        env.priceBookPins.items.filter { ($0.type ?? itemType).uppercased() == itemType }
    }

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            if let error {
                Section { Text(error).foregroundStyle(.red).font(.caption) }
            }

            if isSearching {
                Section("Results") {
                    ForEach(searchResults) { item in
                        itemRow(item)
                    }
                }
            } else {
                Section {
                    Picker("Tab", selection: $tab) {
                        ForEach(BrowseTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                if tab == .favorites {
                    Section("Favorites") {
                        if favorites.isEmpty {
                            Text("Star items to add them here.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(favorites) { item in
                                itemRow(item)
                            }
                        }
                    }
                } else {
                    Section("Categories") {
                        ForEach(categories) { category in
                            NavigationLink(value: category) {
                                Text(category.name)
                            }
                        }
                    }

                    if !frequent.isEmpty {
                        Section("Frequently used items") {
                            ForEach(frequent) { item in
                                itemRow(item)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, prompt: "Search")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create new \(title.lowercased().dropLast())")
            }
        }
        .navigationDestination(for: PriceBookCategoryDTO.self) { category in
            PriceBookCategoryItemsAddView(
                owner: owner,
                category: category,
                itemType: itemType,
                optionId: optionId,
                onAdded: onAdded
            )
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                CreatePriceBookItemSheet(itemType: itemType) { created in
                    await addItem(created)
                }
            }
        }
        .task { await loadBrowse() }
        .onChange(of: search) { _, value in
            Task { await loadSearch(value) }
        }
        .overlay { if isLoading { ProgressView() } }
    }

    @ViewBuilder
    private func itemRow(_ item: PriceBookItemDTO) -> some View {
        Button {
            Task { await addItem(item) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let description = item.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Button {
                        env.priceBookPins.toggle(item)
                    } label: {
                        Image(systemName: env.priceBookPins.isPinned(item.id) ? "star.fill" : "star")
                            .foregroundStyle(StormTheme.sky)
                    }
                    .buttonStyle(.plain)
                    Text(item.resolvedUnitPrice, format: .currency(code: "USD"))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func loadBrowse() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let cats: [PriceBookCategoryDTO] = env.apiClient.get(
                path: APIPath.priceBookCategories,
                query: [URLQueryItem(name: "type", value: itemType)]
            )
            async let freq: FrequentItemsResponse = env.apiClient.get(
                path: APIPath.priceBookFrequentItems,
                query: [
                    URLQueryItem(name: "type", value: itemType),
                    URLQueryItem(name: "limit", value: "20"),
                ]
            )
            categories = try await cats
            frequent = (try? await freq)?.items ?? []
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func loadSearch(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchResults = []
            return
        }
        do {
            searchResults = try await env.apiClient.get(
                path: APIPath.priceBookItems,
                query: [
                    URLQueryItem(name: "q", value: q),
                    URLQueryItem(name: "type", value: itemType),
                ]
            )
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func addItem(_ item: PriceBookItemDTO) async {
        struct Body: Encodable {
            let priceBookItemId: String
            let name: String
            let description: String?
            let unitPrice: Double
            let quantity: Double
            let unit: String?
            let optionId: String?
        }
        do {
            let _: EmptyResponse = try await env.apiClient.post(
                path: owner.lineItemsPath,
                body: Body(
                    priceBookItemId: item.id,
                    name: item.name,
                    description: item.description,
                    unitPrice: item.resolvedUnitPrice,
                    quantity: 1,
                    unit: item.unit,
                    optionId: optionId
                )
            )
            await onAdded()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct PriceBookCategoryItemsAddView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let owner: LineItemsOwner
    let category: PriceBookCategoryDTO
    let itemType: String
    var optionId: String?
    var onAdded: () async -> Void

    @State private var items: [PriceBookItemDTO] = []
    @State private var children: [PriceBookCategoryDTO] = []
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        List {
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            if !children.isEmpty {
                Section("Categories") {
                    ForEach(children) { child in
                        NavigationLink(value: child) {
                            Text(child.name)
                        }
                    }
                }
            }
            Section(category.name) {
                ForEach(items) { item in
                    Button {
                        Task { await add(item) }
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                if let description = item.description, !description.isEmpty {
                                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Button {
                                    env.priceBookPins.toggle(item)
                                } label: {
                                    Image(systemName: env.priceBookPins.isPinned(item.id) ? "star.fill" : "star")
                                        .foregroundStyle(StormTheme.sky)
                                }
                                .buttonStyle(.plain)
                                Text(item.resolvedUnitPrice, format: .currency(code: "USD"))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(category.name)
        .navigationDestination(for: PriceBookCategoryDTO.self) { child in
            PriceBookCategoryItemsAddView(
                owner: owner,
                category: child,
                itemType: itemType,
                optionId: optionId,
                onAdded: onAdded
            )
        }
        .task { await load() }
        .overlay { if isLoading { ProgressView() } }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let detail: PriceBookCategoryDetailDTO = env.apiClient.get(path: APIPath.priceBookCategory(category.id))
            async let list: [PriceBookItemDTO] = env.apiClient.get(
                path: APIPath.priceBookItems,
                query: [
                    URLQueryItem(name: "categoryId", value: category.id),
                    URLQueryItem(name: "type", value: itemType),
                ]
            )
            children = (try? await detail)?.children ?? []
            items = try await list
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func add(_ item: PriceBookItemDTO) async {
        struct Body: Encodable {
            let priceBookItemId: String
            let name: String
            let description: String?
            let unitPrice: Double
            let quantity: Double
            let unit: String?
            let optionId: String?
        }
        do {
            let _: EmptyResponse = try await env.apiClient.post(
                path: owner.lineItemsPath,
                body: Body(
                    priceBookItemId: item.id,
                    name: item.name,
                    description: item.description,
                    unitPrice: item.resolvedUnitPrice,
                    quantity: 1,
                    unit: item.unit,
                    optionId: optionId
                )
            )
            await onAdded()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct CreatePriceBookItemSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let itemType: String
    var onCreated: (PriceBookItemDTO) async -> Void

    @State private var name = ""
    @State private var unitPrice = ""
    @State private var unit = "each"
    @State private var categories: [PriceBookCategoryDTO] = []
    @State private var categoryId: String?
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Unit price", text: $unitPrice)
                    .keyboardType(.decimalPad)
                TextField("Unit", text: $unit)
                Picker("Category", selection: $categoryId) {
                    Text("Select…").tag(String?.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle(itemType == "MATERIAL" ? "New material" : "New service")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { Task { await create() } }
                    .disabled(isSaving)
            }
        }
        .task {
            categories = (try? await env.apiClient.get(
                path: APIPath.priceBookCategories,
                query: [URLQueryItem(name: "type", value: itemType)]
            )) ?? []
            if categoryId == nil {
                categoryId = categories.first?.id
            }
        }
    }

    private func create() async {
        guard let categoryId,
              let price = Double(unitPrice.trimmingCharacters(in: .whitespacesAndNewlines)),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            error = "Name, category, and price are required"
            return
        }
        isSaving = true
        defer { isSaving = false }
        struct Body: Encodable {
            let categoryId: String
            let name: String
            let unitPrice: Double
            let unit: String
            let type: String
            let pricingMode: String
        }
        do {
            let created: PriceBookItemDTO = try await env.apiClient.post(
                path: APIPath.priceBookItems,
                body: Body(
                    categoryId: categoryId,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    unitPrice: price,
                    unit: unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "each" : unit,
                    type: itemType,
                    pricingMode: "MANUAL"
                )
            )
            await onCreated(created)
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
