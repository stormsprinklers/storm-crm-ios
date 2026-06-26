import SwiftUI

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published var jobs: [VisitDTO] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(api: APIClient) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let formatter = ISO8601DateFormatter()

        do {
            jobs = try await api.get(
                path: APIPath.mobileSchedule,
                query: [
                    URLQueryItem(name: "start", value: formatter.string(from: start)),
                    URLQueryItem(name: "end", value: formatter.string(from: end)),
                ]
            )
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct ScheduleView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var viewModel = ScheduleViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.jobs.isEmpty {
                    ProgressView("Loading schedule…")
                } else if let error = viewModel.error {
                    ContentUnavailableView("Could not load schedule", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if viewModel.jobs.isEmpty {
                    ContentUnavailableView("No jobs this week", systemImage: "calendar")
                } else {
                    List(viewModel.jobs) { job in
                        NavigationLink(value: job) {
                            ScheduleRow(job: job)
                        }
                    }
                }
            }
            .navigationTitle("My Schedule")
            .navigationDestination(for: VisitDTO.self) { job in
                VisitDetailView(visitId: job.id)
            }
            .refreshable { await viewModel.load(api: env.apiClient) }
            .task { await viewModel.load(api: env.apiClient) }
        }
    }
}

struct ScheduleRow: View {
    let job: VisitDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.title).font(.headline)
            if let customer = job.customer {
                Text(customer.name).foregroundStyle(.secondary)
            }
            HStack {
                Text(formatDate(job.startAt))
                Spacer()
                StatusBadge(status: job.status)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status.replacingOccurrences(of: "_", with: " "))
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.quaternary)
            .clipShape(Capsule())
    }
}
