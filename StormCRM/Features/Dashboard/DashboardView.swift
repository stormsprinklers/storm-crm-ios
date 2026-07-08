import SwiftUI

struct DashboardWeeklyStats: Equatable {
    let avgJobValue: String
    let fiveStarReviews: String
    let totalRevenue: String
    let rangeLabel: String
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var nextJob: VisitDTO?
    @Published var weeklyStats: DashboardWeeklyStats?
    @Published var isLoading = false
    @Published var error: String?

    func load(api: APIClient, user: UserDTO?) async {
        isLoading = nextJob == nil && weeklyStats == nil
        error = nil
        defer { isLoading = false }

        async let scheduleLoad: Void = loadNextJob(api: api)
        async let statsLoad: Void = loadWeeklyStats(api: api, user: user)

        _ = await (scheduleLoad, statsLoad)
    }

    func refresh(api: APIClient, user: UserDTO?) async {
        await load(api: api, user: user)
    }

    private func loadNextJob(api: APIClient) async {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let endDay = calendar.date(byAdding: .day, value: 14, to: start),
              let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDay)
        else { return }

        do {
            let jobs: [VisitDTO] = try await api.get(
                path: APIPath.mobileSchedule,
                query: [
                    URLQueryItem(name: "start", value: APIDateFormatting.queryString(from: start)),
                    URLQueryItem(name: "end", value: APIDateFormatting.queryString(from: end)),
                ]
            )
            nextJob = Self.pickNextJob(from: jobs)
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func loadWeeklyStats(api: APIClient, user: UserDTO?) async {
        guard let user else { return }
        let range = ReportDateRange.currentWeek

        do {
            let report: KpiDashboardReport = try await api.get(
                path: APIPath.reporting(ReportKind.kpiDashboard.rawValue),
                query: range.queryItems
            )
            weeklyStats = Self.stats(for: user, from: report)
        } catch {
            if self.error == nil {
                self.error = (error as? APIError)?.message ?? error.localizedDescription
            }
        }
    }

    static func pickNextJob(from jobs: [VisitDTO]) -> VisitDTO? {
        let terminal = Set(["COMPLETED", "CANCELLED"])
        let activeStatuses = Set(["EN_ROUTE", "IN_PROGRESS", "PAUSED"])
        let now = Date()

        if let active = jobs.first(where: { activeStatuses.contains($0.status) }) {
            return active
        }

        return jobs
            .filter { !terminal.contains($0.status) }
            .sorted { lhs, rhs in
                let left = APIDateFormatting.parse(lhs.startAt) ?? .distantFuture
                let right = APIDateFormatting.parse(rhs.startAt) ?? .distantFuture
                return left < right
            }
            .first { job in
                guard let start = APIDateFormatting.parse(job.startAt) else { return false }
                return start >= now
            }
    }

    static func stats(for user: UserDTO, from report: KpiDashboardReport) -> DashboardWeeklyStats? {
        let people: [KpiPersonCard]
        switch user.role {
        case "TECH":
            people = report.technicians
        case "INSTALLER":
            people = report.installers ?? []
        case "CSR":
            people = report.csrs
        case "SALES":
            people = report.salespeople
        default:
            return nil
        }

        guard let card = people.first(where: { $0.id == user.id }) else { return nil }

        let avgJobValue = card.metrics.metricValue(label: "Average ticket")
            ?? card.metrics.metricValue(label: "Avg job size")
            ?? "—"
        let fiveStar = card.metrics.metricValue(label: "5-star reviews") ?? "0"
        let revenue = card.metrics.metricValue(label: "Total revenue")
            ?? card.metrics.metricValue(label: "Total revenue sold")
            ?? "—"

        return DashboardWeeklyStats(
            avgJobValue: avgJobValue,
            fiveStarReviews: fiveStar,
            totalRevenue: revenue,
            rangeLabel: report.rangeLabel
        )
    }
}

struct DashboardView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var auth: AuthManager
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var clock = TimeClockViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let user = auth.user {
                        greetingSection(user: user)
                    }

                    clockSection

                    nextJobSection

                    weeklyStatsSection
                }
                .padding()
            }
            .background(StormTheme.page.ignoresSafeArea())
            .navigationTitle("Dashboard")
            .refreshable {
                async let dashboard: Void = viewModel.refresh(api: env.apiClient, user: auth.user)
                async let clockLoad: Void = clock.load(api: env.apiClient)
                _ = await (dashboard, clockLoad)
            }
            .task {
                async let dashboard: Void = viewModel.load(api: env.apiClient, user: auth.user)
                async let clockLoad: Void = clock.load(api: env.apiClient)
                _ = await (dashboard, clockLoad)
            }
            .navigationDestination(for: VisitDTO.self) { job in
                VisitDetailView(visitId: job.id)
            }
        }
    }

    @ViewBuilder
    private func greetingSection(user: UserDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(user.name)
                .font(.title2.bold())
                .foregroundStyle(StormTheme.navy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var clockSection: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                StormSectionHeader(title: "Shift clock", systemImage: "clock")

                if let error = clock.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                if let open = clock.response?.openEntry {
                    Text("Clocked in since \(APIDateFormatting.displayString(from: open.clockInAt))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Clock out", role: .destructive) {
                        Task { await clock.toggle(api: env.apiClient) }
                    }
                    .buttonStyle(StormPrimaryButtonStyle())
                } else {
                    Button("Clock in") {
                        Task { await clock.toggle(api: env.apiClient) }
                    }
                    .buttonStyle(StormPrimaryButtonStyle())
                }

                if let hours = clock.response?.todayHours {
                    Text("Today: \(hours, format: .number.precision(.fractionLength(2))) hours")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var nextJobSection: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                StormSectionHeader(title: nextJobHeaderTitle, systemImage: "mappin.and.ellipse")

                if viewModel.isLoading && viewModel.nextJob == nil {
                    ProgressView()
                } else if let job = viewModel.nextJob {
                    NavigationLink(value: job) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(job.title)
                                .font(.headline)
                                .foregroundStyle(StormTheme.navy)
                            if let customer = job.customer {
                                Text(customer.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text(APIDateFormatting.displayString(from: job.startAt))
                                Spacer()
                                StatusBadge(status: job.status)
                            }
                            .font(.subheadline)
                            if let address = formattedAddress(job) {
                                Text(address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("No upcoming jobs in the next two weeks.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var nextJobHeaderTitle: String {
        guard let status = viewModel.nextJob?.status else { return "Next job" }
        let active = Set(["EN_ROUTE", "IN_PROGRESS", "PAUSED"])
        return active.contains(status) ? "Current job" : "Next job"
    }

    @ViewBuilder
    private var weeklyStatsSection: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                StormSectionHeader(title: "This week", systemImage: "chart.bar")

                if let stats = viewModel.weeklyStats {
                    Text(stats.rangeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        DashboardStatTile(label: "Avg job value", value: stats.avgJobValue)
                        DashboardStatTile(label: "5-star reviews", value: stats.fiveStarReviews)
                        DashboardStatTile(label: "Total revenue", value: stats.totalRevenue)
                    }
                } else if viewModel.isLoading {
                    ProgressView()
                } else {
                    Text("Weekly stats will appear here once you complete jobs this week.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formattedAddress(_ job: VisitDTO) -> String? {
        if let address = AppleMapsURL.formattedAddress(
            street: job.address,
            city: job.city,
            state: job.state,
            zip: job.zip
        ) {
            return address
        }
        if let property = job.property {
            return AppleMapsURL.formattedAddress(
                street: property.address,
                city: property.city,
                state: property.state,
                zip: property.zip
            )
        }
        return nil
    }
}

private struct DashboardStatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(StormTheme.navy)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(StormTheme.ice.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
