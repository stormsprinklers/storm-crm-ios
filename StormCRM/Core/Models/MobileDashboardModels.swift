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

        init(unreadSms: Int, missedTransfers: Int, timerLeftRunning: Bool) {
            self.unreadSms = unreadSms
            self.missedTransfers = missedTransfers
            self.timerLeftRunning = timerLeftRunning
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Only true unread keys — `unansweredSms` means "needs reply" and was falsely
            // showing "1 unread customer text" after threads were already opened.
            unreadSms = Self.decodeCount(in: container, keys: [.unreadSms, .unreadSMS])
            missedTransfers = Self.decodeCount(in: container, keys: [.missedTransfers, .missedTransferCount])
            timerLeftRunning = (try? container.decode(Bool.self, forKey: .timerLeftRunning)) ?? false
        }

        func withUnreadSms(_ value: Int) -> AlertsDTO {
            AlertsDTO(
                unreadSms: max(0, value),
                missedTransfers: missedTransfers,
                timerLeftRunning: timerLeftRunning
            )
        }

        private enum CodingKeys: String, CodingKey {
            case unreadSms
            case unreadSMS
            case missedTransfers
            case missedTransferCount
            case timerLeftRunning
        }

        private static func decodeCount(in container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> Int {
            for key in keys {
                guard container.contains(key) else { continue }
                if (try? container.decodeNil(forKey: key)) == true { continue }
                if let value = try? container.decode(Int.self, forKey: key) { return max(0, value) }
                if let value = try? container.decode(Double.self, forKey: key) { return max(0, Int(value)) }
                if let value = try? container.decode(Bool.self, forKey: key) { return value ? 1 : 0 }
                if let text = try? container.decode(String.self, forKey: key) {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let value = Int(trimmed) { return max(0, value) }
                    if let value = Double(trimmed) { return max(0, Int(value)) }
                }
            }
            return 0
        }
    }

    let clock: ClockDTO?
    let openSegment: TechTimeSegmentDTO?
    let activeVisit: VisitDTO?
    let nextJob: VisitDTO?
    let todayVisits: [VisitDTO]
    let remainingToday: Int
    let alerts: AlertsDTO

    init(
        clock: ClockDTO?,
        openSegment: TechTimeSegmentDTO?,
        activeVisit: VisitDTO?,
        nextJob: VisitDTO?,
        todayVisits: [VisitDTO],
        remainingToday: Int,
        alerts: AlertsDTO
    ) {
        self.clock = clock
        self.openSegment = openSegment
        self.activeVisit = activeVisit
        self.nextJob = nextJob
        self.todayVisits = todayVisits
        self.remainingToday = remainingToday
        self.alerts = alerts
    }
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
