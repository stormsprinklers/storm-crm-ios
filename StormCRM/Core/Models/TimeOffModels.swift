import Foundation

struct TimeOffRequestDTO: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let userName: String
    let startAt: String
    let endAt: String
    let allDay: Bool
    let type: String
    let status: String
    let reason: String?
    let reviewNotes: String?
    let reviewedByName: String?
    let reviewedAt: String?
    let createdByName: String
    let createdAt: String
}

struct TimeOffListResponse: Codable {
    let requests: [TimeOffRequestDTO]
}

enum TimeOffRequestType: String, CaseIterable, Identifiable {
    case timeOff = "TIME_OFF"
    case pto = "PTO"
    case sick = "SICK"
    case other = "OTHER"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeOff: return "Time off"
        case .pto: return "PTO"
        case .sick: return "Sick"
        case .other: return "Other"
        }
    }
}
