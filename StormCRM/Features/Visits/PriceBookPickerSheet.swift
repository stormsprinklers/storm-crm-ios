import SwiftUI

private enum PriceBookTypeFilter: String, CaseIterable, Identifiable {
    case service = "SERVICE"
    case material = "MATERIAL"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .service: return "Services"
        case .material: return "Materials"
        }
    }
}

struct PriceBookPickerSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var priceBookPins: PriceBookPinStore
    @Environment(\.dismiss) private var dismiss
    let onSelect: (PriceBookItemDTO) async -> Void

    @State private var search = ""
    @State private var typeFilter: PriceBookTypeFilter = .service
    @State private var categories: [PriceBookCategoryDTO] = []
    @State private var searchResults: [PriceBookItemDTO] = []
    @State private var isLoading = false
    @State private var error: String?

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    searchResultsList
                } else {
                    browseList
                }
            }
            .overlay {
                if isLoading { ProgressView() }
            }
            .navigationTitle("Price book")
            .searchable(text: $search, prompt: "Search services and materials")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: typeFilter) {
                guard !isSearching else { return }
                await loadCategories()
            }
            .onChange(of: search) { _, newValue in
                Task { await loadSearch(query: newValue) }
            }
        }
    }

    @ViewBuilder
    private var browseList: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red)
            }

            if !priceBookPins.items.isEmpty {
                Section("Pinned") {
                    ForEach(priceBookPins.items) { item in
                        PriceBookPickerRow(item: item) {
                            await select(item)
                        } onTogglePin: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                priceBookPins.toggle(item)
                            }
                        }
                    }
                }
            }

            Section {
                Picker("Type", selection: $typeFilter) {
                    ForEach(PriceBookTypeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if categories.isEmpty, !isLoading {
                Text("No categories yet.")
                    .foregroundStyle(.secondary)
            } else {
                Section(typeFilter.title) {
                    ForEach(categories) { category in
                        NavigationLink {
                            PriceBookCategoryBrowseView(
                                categoryId: category.id,
                                categoryName: category.name,
                                onSelect: { item in await select(item) }
                            )
                        } label: {
                            PriceBookCategoryRow(category: category)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var searchResultsList: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red)
            }

            if searchResults.isEmpty, !isLoading {
                Text("No items found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groupedSearchResults, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.items) { item in
                            PriceBookPickerRow(item: item) {
                                await select(item)
                            } onTogglePin: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    priceBookPins.toggle(item)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var groupedSearchResults: [(title: String, items: [PriceBookItemDTO])] {
        let grouped = Dictionary(grouping: searchResults) { item in
            item.displayCategoryName ?? "Other"
        }
        return grouped.keys.sorted().map { key in
            (title: key, items: grouped[key] ?? [])
        }
    }

    private func select(_ item: PriceBookItemDTO) async {
        await onSelect(item)
        dismiss()
    }

    private func loadCategories() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            categories = try await env.apiClient.get(
                path: APIPath.priceBookCategories,
                query: [URLQueryItem(name: "type", value: typeFilter.rawValue)]
            )
        } catch {
            self.error = (error as? APIError)?.message
            categories = []
        }
    }

    private func loadSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            error = nil
            return
        }

        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        guard search.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            searchResults = try await env.apiClient.get(
                path: APIPath.priceBookItems,
                query: [URLQueryItem(name: "q", value: trimmed)]
            )
        } catch {
            self.error = (error as? APIError)?.message
            searchResults = []
        }
    }
}

private struct PriceBookCategoryBrowseView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var priceBookPins: PriceBookPinStore

    let categoryId: String
    let categoryName: String
    let onSelect: (PriceBookItemDTO) async -> Void

    @State private var childCategories: [PriceBookCategoryDTO] = []
    @State private var items: [PriceBookItemDTO] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red)
            }

            if !childCategories.isEmpty {
                Section("Subcategories") {
                    ForEach(childCategories) { child in
                        NavigationLink {
                            PriceBookCategoryBrowseView(
                                categoryId: child.id,
                                categoryName: child.name,
                                onSelect: onSelect
                            )
                        } label: {
                            PriceBookCategoryRow(category: child)
                        }
                    }
                }
            }

            if items.isEmpty, childCategories.isEmpty, !isLoading {
                Text("No items in this category.")
                    .foregroundStyle(.secondary)
            } else if !items.isEmpty {
                Section(categoryName) {
                    ForEach(items) { item in
                        PriceBookPickerRow(item: item) {
                            await onSelect(item)
                        } onTogglePin: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                priceBookPins.toggle(item)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(categoryName)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading { ProgressView() }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        async let categoryRequest: PriceBookCategoryDetailDTO? = try? env.apiClient.get(
            path: APIPath.priceBookCategory(categoryId)
        )
        async let itemsRequest: [PriceBookItemDTO]? = try? env.apiClient.get(
            path: APIPath.priceBookItems,
            query: [URLQueryItem(name: "categoryId", value: categoryId)]
        )

        let loadedCategory = await categoryRequest
        let loadedItems = await itemsRequest

        if let loadedCategory {
            childCategories = loadedCategory.children ?? []
        } else {
            error = "Category could not be loaded"
            childCategories = []
        }

        items = loadedItems ?? []
        if loadedItems == nil, error == nil {
            error = "Items could not be loaded"
        }
    }
}

private struct PriceBookCategoryRow: View {
    let category: PriceBookCategoryDTO

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.headline)
                    .foregroundStyle(StormTheme.navy)
                if let itemCount = category.itemCount, itemCount > 0 {
                    Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let childCount = category.childCount, childCount > 0 {
                    Text("\(childCount) subcategor\(childCount == 1 ? "y" : "ies")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct PriceBookPickerRow: View {
    @EnvironmentObject private var priceBookPins: PriceBookPinStore

    let item: PriceBookItemDTO
    let onSelect: () async -> Void
    let onTogglePin: () -> Void

    var body: some View {
        let pinned = priceBookPins.isPinned(item.id)
        HStack(alignment: .top, spacing: 10) {
            Button {
                Task { await onSelect() }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(StormTheme.navy)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            if let categoryName = item.displayCategoryName {
                                Text(categoryName)
                            }
                            Text(item.typeLabel)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if let description = item.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(item.resolvedUnitPrice, format: .currency(code: "USD"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Button(action: onTogglePin) {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.body)
                    .foregroundStyle(pinned ? StormTheme.coral : .secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(pinned ? "Unpin item" : "Pin item")
        }
    }
}
