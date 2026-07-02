import SwiftUI

struct PriceBookPickerSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let onSelect: (PriceBookItemDTO) async -> Void

    @State private var search = ""
    @State private var items: [PriceBookItemDTO] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                ForEach(items) { item in
                    Button {
                        Task {
                            await onSelect(item)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).foregroundStyle(StormTheme.navy)
                                if let description = item.description, !description.isEmpty {
                                    Text(description).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(item.resolvedUnitPrice, format: .currency(code: "USD"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if isLoading { ProgressView() }
            }
            .navigationTitle("Price book")
            .searchable(text: $search, prompt: "Search items")
            .onSubmit(of: .search) { Task { await load() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        var query: [URLQueryItem] = []
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            query.append(URLQueryItem(name: "q", value: trimmed))
        }
        do {
            items = try await env.apiClient.get(path: APIPath.priceBookItems, query: query)
            error = nil
        } catch {
            self.error = (error as? APIError)?.message
            items = []
        }
    }
}
