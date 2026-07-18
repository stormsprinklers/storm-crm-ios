import SwiftUI

/// In-app reporting entry — only the full KPI dashboard is available on iOS.
struct ReportingHubView: View {
    var body: some View {
        ReportDetailView(kind: .kpiDashboard)
    }
}

struct ReportDetailView: View {
    init(kind: ReportKind) {
        // iOS only surfaces the KPI dashboard; other report kinds remain web-only.
        _ = kind
    }

    var body: some View {
        KpiDashboardReportView()
            .navigationTitle(ReportKind.kpiDashboard.title)
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
