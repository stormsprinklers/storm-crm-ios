import Foundation
import SwiftUI

@MainActor
final class TechDashboardViewModel: ObservableObject {
    @Published var dashboard: MobileDashboardDTO?
    @Published var isLoading = false
    @Published var error: String?

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
}
