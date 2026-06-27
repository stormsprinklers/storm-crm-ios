import Foundation

enum ReportKind: String, CaseIterable, Identifiable, Hashable {
    case insights
    case kpiDashboard = "kpi-dashboard"
    case techPerformance = "tech-performance"
    case financial
    case csr
    case estimates
    case leads
    case voice
    case invoices
    case payments
    case servicePlansChurn = "service-plans-churn"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .insights: return "Business insights"
        case .kpiDashboard: return "KPI dashboard"
        case .techPerformance: return "Tech performance"
        case .financial: return "Financial trends"
        case .csr: return "CSR calls"
        case .estimates: return "Estimates"
        case .leads: return "Leads"
        case .voice: return "Voice summary"
        case .invoices: return "AR aging"
        case .payments: return "Payments"
        case .servicePlansChurn: return "Service plan churn"
        }
    }

    var subtitle: String {
        switch self {
        case .insights: return "Revenue, pipeline, and collection KPIs"
        case .kpiDashboard: return "Company and team performance — adjustable date range"
        case .techPerformance: return "YTD technician leaderboard"
        case .financial: return "Invoiced vs collected — 12 months"
        case .csr: return "Call volume and booking rates — 30 days"
        case .estimates: return "Estimate funnel and conversion"
        case .leads: return "Lead status and sources"
        case .voice: return "Missed calls and duration — 30 days"
        case .invoices: return "Open invoice aging buckets"
        case .payments: return "Payments by method"
        case .servicePlansChurn: return "Maintenance plan churn MTD"
        }
    }

    var systemImage: String {
        switch self {
        case .insights: return "lightbulb"
        case .kpiDashboard: return "chart.bar.doc.horizontal"
        case .techPerformance: return "person.3"
        case .financial: return "dollarsign.circle"
        case .csr: return "phone"
        case .estimates: return "doc.text"
        case .leads: return "person.crop.circle.badge.plus"
        case .voice: return "phone.connection"
        case .invoices: return "doc.plaintext"
        case .payments: return "creditcard"
        case .servicePlansChurn: return "arrow.triangle.2.circlepath"
        }
    }
}

enum ReportDateRangePreset: String, CaseIterable, Identifiable {
    case ytd, mtd, last30

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ytd: return "Year to date"
        case .mtd: return "Month to date"
        case .last30: return "Last 30 days"
        }
    }
}

struct ReportDateRange: Equatable {
    enum Selection: Equatable {
        case preset(ReportDateRangePreset)
        case custom(start: Date, end: Date)
    }

    var selection: Selection

    static let `default` = ReportDateRange(selection: .preset(.ytd))

    var displayLabel: String {
        switch selection {
        case .preset(let preset):
            return preset.label
        case .custom(let start, let end):
            let startText = start.formatted(date: .abbreviated, time: .omitted)
            let endText = end.formatted(date: .abbreviated, time: .omitted)
            return "\(startText) – \(endText)"
        }
    }

    var queryItems: [URLQueryItem] {
        switch selection {
        case .preset(let preset):
            return [URLQueryItem(name: "range", value: preset.rawValue)]
        case .custom(let start, let end):
            return [
                URLQueryItem(name: "range", value: "custom"),
                URLQueryItem(name: "start", value: APIDateFormatting.dateOnlyString(from: start)),
                URLQueryItem(name: "end", value: APIDateFormatting.dateOnlyString(from: end)),
            ]
        }
    }
}

struct ReportMetric: Decodable, Hashable {
    let label: String
    let value: String

    init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

struct InsightsReport: Decodable {
    let cards: [ReportMetric]
}

struct KpiPersonCard: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let photoUrl: String?
    let color: String?
    let metrics: [ReportMetric]
}

struct KpiCrewCard: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let color: String
    let metrics: [ReportMetric]
}

struct KpiDashboardReport: Decodable {
    let range: String
    let rangeLabel: String
    let company: [ReportMetric]
    let technicians: [KpiPersonCard]
    let installers: [KpiPersonCard]
    let csrs: [KpiPersonCard]
    let crews: [KpiCrewCard]
    let salespeople: [KpiPersonCard]
}

struct TechPerformanceRow: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let visitsCompleted: Int
    let revenue: Double
    let revenueFormatted: String
    let avgJobSize: String
    let hours: Double

    enum CodingKeys: String, CodingKey {
        case id, name, visitsCompleted, revenue, revenueFormatted, avgJobSize, hours
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        visitsCompleted = try container.decodeIfPresent(Int.self, forKey: .visitsCompleted) ?? 0
        revenue = try container.decodeFlexibleDouble(forKey: .revenue) ?? 0
        revenueFormatted = try container.decodeIfPresent(String.self, forKey: .revenueFormatted) ?? ""
        avgJobSize = try container.decodeIfPresent(String.self, forKey: .avgJobSize) ?? ""
        hours = try container.decodeFlexibleDouble(forKey: .hours) ?? 0
    }
}

struct TechPerformanceReport: Decodable {
    let rows: [TechPerformanceRow]
}

struct FinancialMonthRow: Decodable, Identifiable, Hashable {
    var id: String { month }
    let month: String
    let revenue: Double
    let payments: Double

    enum CodingKeys: String, CodingKey {
        case month, revenue, payments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        month = try container.decode(String.self, forKey: .month)
        revenue = try container.decodeFlexibleDouble(forKey: .revenue) ?? 0
        payments = try container.decodeFlexibleDouble(forKey: .payments) ?? 0
    }
}

struct FinancialReport: Decodable {
    let months: [FinancialMonthRow]
}

struct CsrDailyRow: Decodable, Identifiable, Hashable {
    var id: String { date }
    let date: String
    let inbound: Int
    let outbound: Int
}

struct CsrDisposition: Decodable {
    let booked: Int
    let notBooked: Int
    let nonOpportunity: Int
    let none: Int
    let bookRate: Int
    let nonOpportunityRate: Int
}

struct CsrAgentRow: Decodable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let total: Int
    let booked: Int
    let bookRate: Int
}

struct CsrReport: Decodable {
    let daily: [CsrDailyRow]
    let inbound: Int
    let outbound: Int
    let totalCalls: Int
    let avgDurationSeconds: Int
    let disposition: CsrDisposition
    let byAgent: [CsrAgentRow]
}

struct EstimateStatusRow: Decodable, Identifiable, Hashable {
    var id: String { status }
    let status: String
    let count: Int
    let total: Double
    let totalFormatted: String

    enum CodingKeys: String, CodingKey {
        case status, count, total, totalFormatted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        total = try container.decodeFlexibleDouble(forKey: .total) ?? 0
        totalFormatted = try container.decodeIfPresent(String.self, forKey: .totalFormatted) ?? ""
    }
}

struct EstimatesReport: Decodable {
    let conversionRate: Int
    let byStatus: [EstimateStatusRow]
}

struct LeadStatusRow: Decodable, Identifiable, Hashable {
    var id: String { status }
    let status: String
    let count: Int
}

struct LeadSourceRow: Decodable, Identifiable, Hashable {
    var id: String { source }
    let source: String
    let count: Int
}

struct LeadsReport: Decodable {
    let total: Int
    let byStatus: [LeadStatusRow]
    let bySource: [LeadSourceRow]
}

struct VoiceReport: Decodable {
    let total: Int
    let missed: Int
    let avgDurationSeconds: Int
}

struct InvoiceBucketRow: Decodable, Identifiable, Hashable {
    var id: String { label }
    let label: String
    let count: Int
    let total: Double
    let totalFormatted: String

    enum CodingKeys: String, CodingKey {
        case label, count, total, totalFormatted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        total = try container.decodeFlexibleDouble(forKey: .total) ?? 0
        totalFormatted = try container.decodeIfPresent(String.self, forKey: .totalFormatted) ?? ""
    }
}

struct InvoicesReport: Decodable {
    let buckets: [InvoiceBucketRow]
}

struct PaymentMethodRow: Decodable, Identifiable, Hashable {
    var id: String { method }
    let method: String
    let count: Int
    let total: Double
    let totalFormatted: String

    enum CodingKeys: String, CodingKey {
        case method, count, total, totalFormatted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decode(String.self, forKey: .method)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        total = try container.decodeFlexibleDouble(forKey: .total) ?? 0
        totalFormatted = try container.decodeIfPresent(String.self, forKey: .totalFormatted) ?? ""
    }
}

struct PaymentsReport: Decodable {
    let refundCount: Int
    let byMethod: [PaymentMethodRow]
}

struct ServicePlansChurnReport: Decodable {
    let activeStart: Int
    let cancelledThisMonth: Int
    let churnRatePercent: Double

    enum CodingKeys: String, CodingKey {
        case activeStart, cancelledThisMonth, churnRatePercent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeStart = try container.decodeIfPresent(Int.self, forKey: .activeStart) ?? 0
        cancelledThisMonth = try container.decodeIfPresent(Int.self, forKey: .cancelledThisMonth) ?? 0
        churnRatePercent = try container.decodeFlexibleDouble(forKey: .churnRatePercent) ?? 0
    }
}
