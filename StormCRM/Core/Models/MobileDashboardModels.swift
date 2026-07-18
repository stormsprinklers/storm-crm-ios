import Foundation

struct MobileDashboardDTO: Decodable {
    struct ClockDTO: Decodable {
        let id: String
        let clockInAt: String
        let clockOutAt: String?
    }

    struct AlertsDTO: Decodable {
        let unreadSms: Int
        let missedTransfers: Int
        let timerLeftRunning: Bool
    }

    let clock: ClockDTO?
    let openSegment: TechTimeSegmentDTO?
    let activeVisit: VisitDTO?
    let nextJob: VisitDTO?
    let todayVisits: [VisitDTO]
    let remainingToday: Int
    let alerts: AlertsDTO
}

struct TechTimeSegmentDTO: Codable, Identifiable, Equatable {
    let id: String
    let category: String
    let visitId: String?
    let startedAt: String
    let endedAt: String?
    let source: String?
    let deviceId: String?
    let leftRunning: Bool?
    let openHours: Double?
}

struct MissedTransfersResponse: Codable {
    let transfers: [MissedTransferDTO]
}

struct MissedTransferDTO: Codable, Identifiable {
    let id: String
    let status: String
    let fromNumber: String?
    let toNumber: String?
    let startedAt: String
    let endedAt: String?
    let transferType: String?
    let customerId: String?
    let visitId: String?
    let customer: CustomerSummaryDTO?
}

struct CustomerSummaryDTO: Codable {
    let id: String
    let name: String
    let phone: String?
}

enum TechTimeCategory: String, CaseIterable, Identifiable {
    case driving = "DRIVING"
    case working = "WORKING"
    case partsRun = "PARTS_RUN"
    case breakTime = "BREAK"
    case shop = "SHOP"
    case training = "TRAINING_MEETING"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .driving: return "Driving"
        case .working: return "Working"
        case .partsRun: return "Parts run"
        case .breakTime: return "Break"
        case .shop: return "Shop"
        case .training: return "Training / meeting"
        }
    }
}
