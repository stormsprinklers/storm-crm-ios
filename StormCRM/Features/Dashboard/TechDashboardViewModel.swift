import Foundation
import SwiftUI

@MainActor
final class TechDashboardViewModel: ObservableObject {
    @Published var dashboard: MobileDashboardDTO?
    @Published var isLoading = false
    @Published var error: String?

    /// Alerts after reconciling dashboard `unreadSms` with the inbox the user can actually see.
    var displayAlerts: MobileDashboardDTO.AlertsDTO? {
        dashboard?.alerts
    }

    func load(api: APIClient, userRole: String? = nil) async {
        isLoading = dashboard == nil
        error = nil
        defer { isLoading = false }
        do {
            var loaded: MobileDashboardDTO = try await api.get(path: APIPath.mobileDashboard)
            if let reconciled = await reconciledUnreadSms(api: api, userRole: userRole) {
                loaded = MobileDashboardDTO(
                    clock: loaded.clock,
                    openSegment: loaded.openSegment,
                    activeVisit: loaded.activeVisit,
                    nextJob: loaded.nextJob,
                    todayVisits: loaded.todayVisits,
                    remainingToday: loaded.remainingToday,
                    alerts: loaded.alerts.withUnreadSms(reconciled)
                )
            }
            dashboard = loaded
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    /// Prefer the inbox list the user can open over the raw dashboard counter, which can stay
    /// stuck at 1 when a conversation is not visible/eligible on mobile.
    private func reconciledUnreadSms(api: APIClient, userRole: String?) async -> Int? {
        let conversations: [ConversationDTO]
        do {
            if UserRoles.isFieldRole(userRole ?? "") {
                conversations = try await api.get(path: APIPath.mobileInboxSms)
            } else {
                conversations = try await api.get(
                    path: APIPath.smsConversations,
                    query: [URLQueryItem(name: "scope", value: InboxScope.customers.apiScope)]
                )
            }
        } catch {
            return nil
        }

        if conversations.isEmpty {
            return 0
        }

        let unread = conversations.reduce(0) { partial, conversation in
            if let count = conversation.unreadCount {
                return partial + max(0, count)
            }
            return partial + (conversation.appearsUnread ? 1 : 0)
        }
        return unread
    }
}
