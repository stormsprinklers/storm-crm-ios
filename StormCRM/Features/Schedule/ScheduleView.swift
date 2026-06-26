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
        let startDay = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: Date())) ?? Date()
        let start = calendar.startOfDay(for: startDay)
        guard let endDay = calendar.date(byAdding: .day, value: 21, to: start) else { return }
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDay) ?? endDay

        do {
            jobs = try await api.get(
                path: APIPath.mobileSchedule,
                query: [
                    URLQueryItem(name: "start", value: APIDateFormatting.queryString(from: start)),
                    URLQueryItem(name: "end", value: APIDateFormatting.queryString(from: end)),
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
                    ContentUnavailableView("No jobs in this range", systemImage: "calendar", description: Text("Nothing scheduled in the past week or next 3 weeks."))
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
        APIDateFormatting.displayString(from: iso)
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
