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

    func load(api: APIClient, user: UserDTO?, offlineSync: OfflineSyncManager?) async {
        isLoading = nextJob == nil && weeklyStats == nil
        error = nil
        defer { isLoading = false }

        async let scheduleLoad: Void = loadNextJob(api: api, offlineSync: offlineSync)
        async let statsLoad: Void = loadWeeklyStats(api: api, user: user)

        _ = await (scheduleLoad, statsLoad)
    }

    func refresh(api: APIClient, user: UserDTO?, offlineSync: OfflineSyncManager?) async {
        await load(api: api, user: user, offlineSync: offlineSync)
    }

    private func loadNextJob(api: APIClient, offlineSync: OfflineSyncManager?) async {
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
            offlineSync?.cacheVisits(jobs)
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
    @StateObject private var techDashboard = TechDashboardViewModel()
    @StateObject private var clock = TimeClockViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !env.offlineSync.isOnline {
                        offlineBanner
                    }

                    if let user = auth.user {
                        greetingSection(user: user)
                    }

                    if let alerts = techDashboard.dashboard?.alerts {
                        alertsSection(alerts)
                    }

                    clockSection
                    categoryTimerSection
                    activeAndNextJobSection
                    remainingTodaySection

                    if !UserRoles.isFieldRole(auth.user?.role ?? "") {
                        weeklyStatsSection
                    }
                }
                .padding()
            }
            .background(StormTheme.page.ignoresSafeArea())
            .navigationTitle("Dashboard")
            .refreshable {
                async let dashboard: Void = viewModel.refresh(api: env.apiClient, user: auth.user, offlineSync: env.offlineSync)
                async let tech: Void = techDashboard.load(api: env.apiClient)
                async let clockLoad: Void = clock.load(api: env.apiClient)
                _ = await (dashboard, tech, clockLoad)
            }
            .task {
                async let dashboard: Void = viewModel.load(api: env.apiClient, user: auth.user, offlineSync: env.offlineSync)
                async let tech: Void = techDashboard.load(api: env.apiClient)
                async let clockLoad: Void = clock.load(api: env.apiClient)
                _ = await (dashboard, tech, clockLoad)
            }
            .navigationDestination(for: VisitDTO.self) { job in
                VisitDetailView(visitId: job.id)
            }
        }
    }

    private var offlineBanner: some View {
        HStack {
            Image(systemName: "wifi.slash")
            Text("You're offline — calls, SMS, Rachio, and card payments need a connection.")
                .font(.caption)
        }
        .foregroundStyle(.orange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func alertsSection(_ alerts: MobileDashboardDTO.AlertsDTO) -> some View {
        let hasAlert = alerts.unreadSms > 0 || alerts.missedTransfers > 0 || alerts.timerLeftRunning
        if hasAlert {
            StormCard {
                VStack(alignment: .leading, spacing: 8) {
                    StormSectionHeader(title: "Alerts", systemImage: "bell")
                    if alerts.timerLeftRunning {
                        Text("A category timer has been running a long time.")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                    if alerts.unreadSms > 0 {
                        Button {
                            env.selectedTab = .messages
                        } label: {
                            Text("\(alerts.unreadSms) unread customer text\(alerts.unreadSms == 1 ? "" : "s")")
                                .font(.subheadline)
                        }
                    }
                    if alerts.missedTransfers > 0 {
                        NavigationLink {
                            MissedTransfersView()
                        } label: {
                            Text("\(alerts.missedTransfers) missed transfer\(alerts.missedTransfers == 1 ? "" : "s")")
                                .font(.subheadline)
                        }
                    }
                }
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

    private var categoryTimerSection: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                StormSectionHeader(title: "Activity timer", systemImage: "timer")

                if let message = techDashboard.segmentMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }

                if let open = techDashboard.dashboard?.openSegment {
                    Text("\(TechTimeCategory(rawValue: open.category)?.title ?? open.category) since \(APIDateFormatting.displayString(from: open.startedAt))")
                        .font(.subheadline)
                    if open.leftRunning == true {
                        Text("Left running — consider stopping this timer.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Button("Stop timer", role: .destructive) {
                        Task { await techDashboard.stopSegment(api: env.apiClient) }
                    }
                    .buttonStyle(StormSecondaryButtonStyle())
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(TechTimeCategory.allCases) { category in
                            Button(category.title) {
                                Task {
                                    await techDashboard.startSegment(
                                        api: env.apiClient,
                                        category: category,
                                        visitId: techDashboard.dashboard?.activeVisit?.id
                                    )
                                }
                            }
                            .buttonStyle(StormSecondaryButtonStyle())
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var activeAndNextJobSection: some View {
        let active = techDashboard.dashboard?.activeVisit
        let next = techDashboard.dashboard?.nextJob ?? viewModel.nextJob
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                if let active {
                    StormSectionHeader(title: "Active job", systemImage: "wrench.and.screwdriver")
                    jobLink(active)
                    if let next, next.id != active.id {
                        Divider()
                        Text("Next up").font(.caption).foregroundStyle(.secondary)
                        jobLink(next)
                    }
                } else {
                    StormSectionHeader(title: nextJobHeaderTitle(for: next), systemImage: "mappin.and.ellipse")
                    if techDashboard.isLoading && next == nil {
                        ProgressView()
                    } else if let job = next {
                        jobLink(job)
                    } else {
                        Text("No upcoming jobs today.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func jobLink(_ job: VisitDTO) -> some View {
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
    }

    @ViewBuilder
    private var remainingTodaySection: some View {
        if let remaining = techDashboard.dashboard?.remainingToday {
            StormCard {
                HStack {
                    StormSectionHeader(title: "Remaining today", systemImage: "calendar")
                    Spacer()
                    Text("\(remaining)")
                        .font(.title2.bold())
                        .foregroundStyle(StormTheme.navy)
                }
            }
        }
    }

    private func nextJobHeaderTitle(for job: VisitDTO?) -> String {
        guard let status = job?.status else { return "Next job" }
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
