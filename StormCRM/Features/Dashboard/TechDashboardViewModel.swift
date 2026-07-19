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

    /// When the inbox list loads, prefer its explicit unread counts over the dashboard counter.
    /// Returns `nil` only if the inbox request fails (keep the dashboard value, which no longer
    /// treats `unansweredSms` as unread).
    private func reconciledUnreadSms(api: APIClient, userRole: String?) async -> Int? {
        let conversations: [ConversationDTO]
        do {
            conversations = try await fetchInboxConversations(api: api, userRole: userRole)
        } catch {
            return nil
        }

        if conversations.isEmpty {
            return 0
        }

        return conversations.reduce(0) { partial, conversation in
            if let count = conversation.unreadCount {
                return partial + max(0, count)
            }
            return partial + (conversation.appearsUnread ? 1 : 0)
        }
    }

    private func fetchInboxConversations(api: APIClient, userRole: String?) async throws -> [ConversationDTO] {
        let response: ConversationsListResponse
        if UserRoles.isFieldRole(userRole ?? "") {
            response = try await api.get(path: APIPath.mobileInboxSms)
        } else {
            response = try await api.get(
                path: APIPath.smsConversations,
                query: [URLQueryItem(name: "scope", value: InboxScope.customers.apiScope)]
            )
        }
        return response.conversations
    }
}
