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

/// Splits KPI metrics into Service (left) and Install (right) columns with row-aligned cells.
private enum KpiMetricLane: String {
    case service
    case install

    var title: String {
        switch self {
        case .service: return "Service"
        case .install: return "Install"
        }
    }

    static func lane(for label: String, preferInstallForAmbiguous: Bool = false) -> KpiMetricLane {
        let key = label.lowercased()
        // Install-leaning labels first so "install booking rate" etc. classify correctly.
        let installTokens = [
            "install",
            "man hour",
            "per man",
            "booked appt",
            "booked appointment",
            "change order",
            "option sold",
            "options sold",
        ]
        if installTokens.contains(where: { key.contains($0) }) {
            return .install
        }
        // Ambiguous revenue/volume metrics follow the card context (e.g. Install Crew A).
        let ambiguousTokens = ["total revenue", "average ticket", "avg job size", "jobs completed", "visits completed"]
        if preferInstallForAmbiguous, ambiguousTokens.contains(where: { key.contains($0) }) {
            return .install
        }
        return .service
    }
}

private enum KpiMetricOrdering {
    static let servicePriority = [
        "booking rate",
        "avg speed to lead",
        "average speed to lead",
        "avg call duration",
        "average call duration",
        "maintenance plans sold",
        "callback rate",
        "5-star reviews",
        "average ticket",
        "avg job size",
        "jobs completed",
        "visits completed",
        "total revenue",
    ]

    static let installPriority = [
        "avg booked appt revenue",
        "average booked appt revenue",
        "install booking rate",
        "booking rate",
        "total revenue",
        "avg per man hour",
        "average per man hour",
        "5-star reviews",
        "callback rate",
        "change orders",
        "options sold",
    ]

    static func sorted(_ metrics: [ReportMetric], lane: KpiMetricLane) -> [ReportMetric] {
        let priority = lane == .service ? servicePriority : installPriority
        return metrics.sorted { lhs, rhs in
            let left = priorityIndex(lhs.label, in: priority)
            let right = priorityIndex(rhs.label, in: priority)
            if left != right { return left < right }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    private static func priorityIndex(_ label: String, in priority: [String]) -> Int {
        let key = label.lowercased()
        if let index = priority.firstIndex(where: { key == $0 || key.contains($0) }) {
            return index
        }
        return priority.count
    }

    static func split(
        _ metrics: [ReportMetric],
        preferInstallForAmbiguous: Bool = false
    ) -> (service: [ReportMetric], install: [ReportMetric]) {
        var service: [ReportMetric] = []
        var install: [ReportMetric] = []
        for metric in metrics {
            switch KpiMetricLane.lane(for: metric.label, preferInstallForAmbiguous: preferInstallForAmbiguous) {
            case .service: service.append(metric)
            case .install: install.append(metric)
            }
        }
        return (sorted(service, lane: .service), sorted(install, lane: .install))
    }
}

private struct KpiMetricCell: View {
    let metric: ReportMetric?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let metric {
                Text(metric.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(metric.value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(StormTheme.navy)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            } else {
                Text(" ")
                    .font(.caption2)
                Text(" ")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
    }
}

private struct ServiceInstallMetricColumns: View {
    let metrics: [ReportMetric]
    var preferInstallForAmbiguous: Bool = false

    private var columns: (service: [ReportMetric], install: [ReportMetric]) {
        KpiMetricOrdering.split(metrics, preferInstallForAmbiguous: preferInstallForAmbiguous)
    }

    var body: some View {
        let split = columns
        let rowCount = max(split.service.count, split.install.count, 1)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(KpiMetricLane.service.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StormTheme.sky)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(KpiMetricLane.install.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StormTheme.sky)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(0..<rowCount, id: \.self) { index in
                HStack(alignment: .top, spacing: 12) {
                    KpiMetricCell(metric: index < split.service.count ? split.service[index] : nil)
                    KpiMetricCell(metric: index < split.install.count ? split.install[index] : nil)
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
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                NamedColorChip(person: NamedColor(
                                    id: person.id,
                                    name: person.name,
                                    color: person.color,
                                    photoUrl: person.photoUrl
                                ))
                                Spacer()
                            }
                            ServiceInstallMetricColumns(metrics: person.metrics)
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
                        VStack(alignment: .leading, spacing: 10) {
                            Text(crew.name).font(.subheadline.bold())
                            ServiceInstallMetricColumns(
                                metrics: crew.metrics,
                                preferInstallForAmbiguous: crew.name.localizedCaseInsensitiveContains("install")
                            )
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
