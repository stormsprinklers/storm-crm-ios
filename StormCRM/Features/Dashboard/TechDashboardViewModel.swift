import Foundation
import SwiftUI

@MainActor
final class TechDashboardViewModel: ObservableObject {
    @Published var dashboard: MobileDashboardDTO?
    @Published var isLoading = false
    @Published var error: String?
    @Published var segmentMessage: String?

    func load(api: APIClient) async {
        isLoading = dashboard == nil
        error = nil
        defer { isLoading = false }
        do {
            dashboard = try await api.get(path: APIPath.mobileDashboard)
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func startSegment(api: APIClient, category: TechTimeCategory, visitId: String?) async {
        struct Body: Encodable {
            let action: String
            let category: String
            let visitId: String?
        }
        do {
            let _: TimeSegmentActionResponse = try await api.post(
                path: APIPath.mobileTimeSegments,
                body: Body(action: "start", category: category.rawValue, visitId: visitId)
            )
            segmentMessage = "Started \(category.title)"
            await load(api: api)
        } catch {
            segmentMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func stopSegment(api: APIClient) async {
        struct Body: Encodable { let action: String }
        do {
            let _: TimeSegmentActionResponse = try await api.post(
                path: APIPath.mobileTimeSegments,
                body: Body(action: "stop")
            )
            segmentMessage = "Timer stopped"
            await load(api: api)
        } catch {
            segmentMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

private struct TimeSegmentActionResponse: Codable {
    let segment: TechTimeSegmentDTO?
}
