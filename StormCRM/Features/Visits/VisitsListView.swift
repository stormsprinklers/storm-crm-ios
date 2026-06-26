import SwiftUI

@MainActor
final class VisitsListViewModel: ObservableObject {
    @Published var visits: [VisitDTO] = []
    @Published var search = ""
    @Published var isLoading = false
    @Published var error: String?

    func load(api: APIClient) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        var query: [URLQueryItem] = []
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            query.append(URLQueryItem(name: "search", value: search))
        }
        do {
            visits = try await api.get(path: APIPath.visits, query: query)
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct VisitsListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var viewModel = VisitsListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.visits.isEmpty {
                    ProgressView()
                } else if let error = viewModel.error {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    List(viewModel.visits) { visit in
                        NavigationLink(value: visit.id) {
                            ScheduleRow(job: visit)
                        }
                    }
                }
            }
            .navigationTitle("Visits")
            .searchable(text: $viewModel.search, prompt: "Search visits")
            .onSubmit(of: .search) { Task { await viewModel.load(api: env.apiClient) } }
            .navigationDestination(for: String.self) { visitId in
                VisitDetailView(visitId: visitId)
            }
            .refreshable { await viewModel.load(api: env.apiClient) }
            .task { await viewModel.load(api: env.apiClient) }
        }
    }
}
