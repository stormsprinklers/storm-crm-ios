import SwiftUI

enum ScheduleColorMode: String, CaseIterable, Identifiable {
    case technician
    case area
    case crew
    case division

    var id: String { rawValue }

    var label: String {
        switch self {
        case .technician: return "Technician"
        case .area: return "Service area"
        case .crew: return "Crew"
        case .division: return "Division"
        }
    }
}

enum ScheduleColors {
    private static let fallbackHex = "#64748B"
    private static let installHex = "#059669"
    private static let serviceHex = "#2563EB"

    static func accentHex(for job: VisitDTO, mode: ScheduleColorMode) -> String {
        switch mode {
        case .technician:
            return job.assignedUser?.color ?? fallbackHex
        case .area:
            return job.serviceArea?.color ?? fallbackHex
        case .crew:
            return job.crew?.color ?? job.assignedUser?.color ?? fallbackHex
        case .division:
            return job.division == "INSTALL" ? installHex : serviceHex
        }
    }

    static func accentColor(for job: VisitDTO, mode: ScheduleColorMode) -> Color {
        Color(hex: accentHex(for: job, mode: mode)) ?? Color(hex: fallbackHex)!
    }

    static func backgroundColor(for job: VisitDTO, mode: ScheduleColorMode) -> Color {
        accentColor(for: job, mode: mode).opacity(0.12)
    }
}
