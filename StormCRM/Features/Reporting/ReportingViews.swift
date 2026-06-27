import SwiftUI

struct ReportingHubView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(value: ReportKind.insights) {
                        ReportHubRow(kind: .insights)
                    }
                    NavigationLink(value: ReportKind.kpiDashboard) {
                        ReportHubRow(kind: .kpiDashboard)
                    }
                } header: {
                    Text("Overview")
                }

                Section("Operations") {
                    ForEach([ReportKind.techPerformance, .csr, .voice]) { kind in
                        NavigationLink(value: kind) {
                            ReportHubRow(kind: kind)
                        }
                    }
                }

                Section("Sales & pipeline") {
                    ForEach([ReportKind.estimates, .leads]) { kind in
                        NavigationLink(value: kind) {
                            ReportHubRow(kind: kind)
                        }
                    }
                }

                Section("Financial") {
                    ForEach([ReportKind.financial, .invoices, .payments]) { kind in
                        NavigationLink(value: kind) {
                            ReportHubRow(kind: kind)
                        }
                    }
                }

                Section("Service plans") {
                    NavigationLink(value: ReportKind.servicePlansChurn) {
                        ReportHubRow(kind: .servicePlansChurn)
                    }
                }
            }
            .navigationTitle("Reporting")
            .navigationDestination(for: ReportKind.self) { kind in
                ReportDetailView(kind: kind)
            }
        }
    }
}

private struct ReportHubRow: View {
    let kind: ReportKind

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.systemImage)
                .font(.title3)
                .foregroundStyle(StormTheme.sky)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.headline)
                Text(kind.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ReportDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    let kind: ReportKind

    var body: some View {
        Group {
            switch kind {
            case .insights:
                InsightsReportView()
            case .kpiDashboard:
                KpiDashboardReportView()
            case .techPerformance:
                TechPerformanceReportView()
            case .financial:
                FinancialReportView()
            case .csr:
                CsrReportView()
            case .estimates:
                EstimatesReportView()
            case .leads:
                LeadsReportView()
            case .voice:
                VoiceReportView()
            case .invoices:
                InvoicesReportView()
            case .payments:
                PaymentsReportView()
            case .servicePlansChurn:
                ServicePlansChurnReportView()
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared components

private struct ReportLoadingShell<Content: View>: View {
    let isLoading: Bool
    let error: String?
    let onRefresh: () async -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading report…")
            } else if let error {
                ContentUnavailableView(
                    "Could not load report",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        content()
                    }
                    .padding()
                }
                .background(StormTheme.page.ignoresSafeArea())
            }
        }
        .refreshable { await onRefresh() }
    }
}

private struct MetricGrid: View {
    let metrics: [ReportMetric]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(metrics, id: \.label) { metric in
                StormCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(metric.value)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(StormTheme.navy)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct PersonCardsSection: View {
    let title: String
    let people: [KpiPersonCard]

    var body: some View {
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: title, systemImage: "person.2")
                ForEach(people) { person in
                    StormCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                NamedColorChip(person: NamedColor(
                                    id: person.id,
                                    name: person.name,
                                    color: person.color,
                                    photoUrl: person.photoUrl
                                ))
                                Spacer()
                            }
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(person.metrics, id: \.label) { metric in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(metric.label).font(.caption2).foregroundStyle(.secondary)
                                        Text(metric.value).font(.subheadline.weight(.semibold))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct CrewCardsSection: View {
    let crews: [KpiCrewCard]

    var body: some View {
        if !crews.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Crews", systemImage: "person.3")
                ForEach(crews) { crew in
                    StormCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(crew.name).font(.subheadline.bold())
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(crew.metrics, id: \.label) { metric in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(metric.label).font(.caption2).foregroundStyle(.secondary)
                                        Text(metric.value).font(.subheadline.weight(.semibold))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold))
        }
    }
}

// MARK: - Insights

private struct InsightsReportView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var report: InsightsReport?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ReportLoadingShell(isLoading: isLoading, error: error, onRefresh: load) {
            if let report {
                MetricGrid(metrics: report.cards)
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = report == nil
        error = nil
        defer { isLoading = false }
        do {
            report = try await env.apiClient.get(path: APIPath.reporting(ReportKind.insights.rawValue))
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

// MARK: - KPI Dashboard

private struct KpiDashboardReportView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var report: KpiDashboardReport?
    @State private var range = ReportDateRange.default
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ReportLoadingShell(isLoading: isLoading, error: error, onRefresh: load) {
            if let report {
                Text("Company overview · \(report.rangeLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !report.company.isEmpty {
                    StormSectionHeader(title: "Company", systemImage: "building.2")
                    MetricGrid(metrics: report.company)
                }

                PersonCardsSection(title: "Technicians", people: report.technicians)
                PersonCardsSection(title: "Installers", people: report.installers)
                PersonCardsSection(title: "CSRs", people: report.csrs)
                CrewCardsSection(crews: report.crews)
                PersonCardsSection(title: "Sales", people: report.salespeople)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ReportDateRangeControl(range: $range)
            }
        }
        .task { await load() }
        .onChange(of: range) { _, _ in Task { await load() } }
    }

    private func load() async {
        isLoading = report == nil
        error = nil
        defer { isLoading = false }
        do {
            report = try await env.apiClient.get(
                path: APIPath.reporting(ReportKind.kpiDashboard.rawValue),
                query: range.queryItems
            )
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

// MARK: - Tech performance

private struct TechPerformanceReportView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var report: TechPerformanceReport?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ReportLoadingShell(isLoading: isLoading, error: error, onRefresh: load) {
            if let report {
                Text("Year to date · sorted by revenue")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(report.rows) { row in
                    StormCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(row.name).font(.headline)
                            StatRow(label: "Revenue", value: row.revenueFormatted)
                            StatRow(label: "Visits completed", value: "\(row.visitsCompleted)")
                            StatRow(label: "Avg job size", value: row.avgJobSize)
                            StatRow(label: "Hours", value: String(format: "%.1f", row.hours))
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = report == nil
        error = nil
        defer { isLoading = false }
        do {
            report = try await env.apiClient.get(path: APIPath.reporting(ReportKind.techPerformance.rawValue))
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

// MARK: - Financial

private struct FinancialReportView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var report: FinancialReport?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ReportLoadingShell(isLoading: isLoading, error: error, onRefresh: load) {
            if let report {
                Text("Rolling 12 months")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(report.months) { month in
                    StormCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(month.month).font(.subheadline.bold())
                            StatRow(label: "Invoiced", value: month.revenue.formatted(.currency(code: "USD")))
                            StatRow(label: "Collected", value: month.payments.formatted(.currency(code: "USD")))
                            FinancialBar(revenue: month.revenue, payments: month.payments)
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = report == nil
        error = nil
        defer { isLoading = false }
        do {
            report = try await env.apiClient.get(path: APIPath.reporting(ReportKind.financial.rawValue))
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

private struct FinancialBar: View {
    let revenue: Double
    let payments: Double

    var body: some View {
        let maxValue = max(revenue, payments, 1)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(StormTheme.sky.opacity(0.7))
                    .frame(width: barWidth(revenue, maxValue: maxValue), height: 8)
                Text("Invoiced").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(StormTheme.success.opacity(0.7))
                    .frame(width: barWidth(payments, maxValue: maxValue), height: 8)
                Text("Collected").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func barWidth(_ value: Double, maxValue: Double) -> CGFloat {
        CGFloat(Swift.max(4, (value / maxValue) * 120))
    }
}

// MARK: - CSR

private struct CsrReportView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var report: CsrReport?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ReportLoadingShell(isLoading: isLoading, error: error, onRefresh: load) {
            if let report {
                Text("Last 30 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                MetricGrid(metrics: [
                    ReportMetric(label: "Total calls", value: "\(report.totalCalls)"),
                    ReportMetric(label: "Inbound", value: "\(report.inbound)"),
                    ReportMetric(label: "Outbound", value: "\(report.outbound)"),
                    ReportMetric(label: "Avg duration", value: formatDuration(report.avgDurationSeconds)),
                    ReportMetric(label: "Book rate", value: "\(report.disposition.bookRate)%"),
                    ReportMetric(label: "Non-opportunity", value: "\(report.disposition.nonOpportunityRate)%"),
                ])

                StormCard {
                    VStack(alignment: .leading, spacing: 8) {
                        StormSectionHeader(title: "Disposition", systemImage: "phone.arrow.down.left")
                        StatRow(label: "Booked", value: "\(report.disposition.booked)")
                        StatRow(label: "Not booked", value: "\(report.disposition.notBooked)")
                        StatRow(label: "Non-opportunity", value: "\(report.disposition.nonOpportunity)")
                        StatRow(label: "Undispositioned", value: "\(report.disposition.none)")
                    }
                }

                if !report.byAgent.isEmpty {
                    StormSectionHeader(title: "By agent", systemImage: "person")
                    ForEach(report.byAgent) { agent in
                        StormCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(agent.name).font(.subheadline.bold())
                                StatRow(label: "Calls", value: "\(agent.total)")
                                StatRow(label: "Booked", value: "\(agent.booked)")
                                StatRow(label: "Book rate", value: "\(agent.bookRate)%")
                            }
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = report == nil
        error = nil
        defer { isLoading = false }
        do {
            report = try await env.apiClient.get(path: APIPath.reporting(ReportKind.csr.rawValue))
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Estimates

private struct EstimatesReportView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var report: EstimatesReport?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ReportLoadingShell(isLoading: isLoading, error: error, onRefresh: load) {
            if let report {
                StormCard {
                    StatRow(label: "Conversion rate", value: "\(report.conversionRate)%")
                }
                ForEach(report.byStatus) { row in
                    StormCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.status.replacingOccurrences(of: "_", with: " "))
                                .font(.subheadline.bold())
                            StatRow(label: "Count", value: "\(row.count)")
                            StatRow(label: "Total", value: row.totalFormatted)
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = report == nil
        error = nil
        defer { isLoading = false }
        do {
            report = try await env.apiClient.get(path: APIPath.reporting(ReportKind.estimates.rawValue))
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

// MARK: - Leads

private struct LeadsReportView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var report: LeadsReport?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ReportLoadingShell(isLoading: isLoading, error: error, onRefresh: load) {
            if let report {
                StormCard {
                    StatRow(label: "Total leads", value: "\(report.total)")
                }

                StormSectionHeader(title: "By status", systemImage: "list.bullet")
                ForEach(report.byStatus.filter { $0.count > 0 }) { row in
                    StormCard {
                        StatRow(
                            label: row.status.replacingOccurrences(of: "_", with: " "),
                            value: "\(row.count)"
                        )
                    }
                }

                StormSectionHeader(title: "By source", systemImage: "arrow.triangle.branch")
                ForEach(report.bySource.sorted(by: { $0.count > $1.count })) { row in
                    StormCard {
                        StatRow(label: row.source, value: "\(row.count)")
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = report == nil
        error = nil
        defer { isLoading = false }
        do {
            report = try await env.apiClient.get(path: APIPath.reporting(ReportKind.leads.rawValue))
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

// MARK: - Voice

private struct VoiceReportView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var report: VoiceReport?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ReportLoadingShell(isLoading: isLoading, error: error, onRefresh: load) {
            if let report {
                Text("Last 30 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                MetricGrid(metrics: [
                    ReportMetric(label: "Total calls", value: "\(report.total)"),
                    ReportMetric(label: "Missed", value: "\(report.missed)"),
                    ReportMetric(label: "Avg duration", value: formatDuration(report.avgDurationSeconds)),
                    ReportMetric(
                        label: "Miss rate",
                        value: report.total > 0
                            ? "\(Int((Double(report.missed) / Double(report.total)) * 100))%"
                            : "0%"
                    ),
                ])
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = report == nil
        error = nil
        defer { isLoading = false }
        do {
            report = try await env.apiClient.get(path: APIPath.reporting(ReportKind.voice.rawValue))
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Invoices

private struct InvoicesReportView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var report: InvoicesReport?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ReportLoadingShell(isLoading: isLoading, error: error, onRefresh: load) {
            if let report {
                Text("Open accounts receivable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(report.buckets) { bucket in
                    StormCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(bucket.label).font(.subheadline.bold())
                            StatRow(label: "Invoices", value: "\(bucket.count)")
                            StatRow(label: "Balance", value: bucket.totalFormatted)
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = report == nil
        error = nil
        defer { isLoading = false }
        do {
            report = try await env.apiClient.get(path: APIPath.reporting(ReportKind.invoices.rawValue))
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

// MARK: - Payments

private struct PaymentsReportView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var report: PaymentsReport?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ReportLoadingShell(isLoading: isLoading, error: error, onRefresh: load) {
            if let report {
                StormCard {
                    StatRow(label: "Refunds", value: "\(report.refundCount)")
                }
                ForEach(report.byMethod.filter { $0.count > 0 }) { row in
                    StormCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.method.replacingOccurrences(of: "_", with: " "))
                                .font(.subheadline.bold())
                            StatRow(label: "Count", value: "\(row.count)")
                            StatRow(label: "Total", value: row.totalFormatted)
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = report == nil
        error = nil
        defer { isLoading = false }
        do {
            report = try await env.apiClient.get(path: APIPath.reporting(ReportKind.payments.rawValue))
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

// MARK: - Service plan churn

private struct ServicePlansChurnReportView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var report: ServicePlansChurnReport?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ReportLoadingShell(isLoading: isLoading, error: error, onRefresh: load) {
            if let report {
                Text("Month to date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                MetricGrid(metrics: [
                    ReportMetric(label: "Active at month start", value: "\(report.activeStart)"),
                    ReportMetric(label: "Cancelled this month", value: "\(report.cancelledThisMonth)"),
                    ReportMetric(label: "Churn rate", value: String(format: "%.1f%%", report.churnRatePercent)),
                ])
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = report == nil
        error = nil
        defer { isLoading = false }
        do {
            report = try await env.apiClient.get(path: APIPath.reporting(ReportKind.servicePlansChurn.rawValue))
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
