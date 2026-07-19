import Foundation

import SwiftData

import SwiftUI



enum MainTab: String, Hashable, CaseIterable, Identifiable {
    case dashboard
    case schedule
    case customers
    case messages
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .schedule: return "Schedule"
        case .customers: return "Customers"
        case .messages: return "Messages"
        case .more: return "More"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "house"
        case .schedule: return "calendar"
        case .customers: return "person.2"
        case .messages: return "message"
        case .more: return "ellipsis.circle"
        }
    }
}



struct InboxCustomerNavigation: Hashable, Identifiable {

    let customerId: String

    let name: String

    let phone: String?



    var id: String { customerId }

}



enum DeepLinkNavigation: Hashable {

    case visit(String)

    case customer(String)

    case estimate(String)

}



@MainActor

final class AppEnvironment: ObservableObject {

    let tokenStore: TokenStore

    let apiClient: APIClient

    let auth: AuthManager

    let branding: CompanyBranding

    let location = LocationManager()

    let voice: VoiceManager

    let priceBookPins = PriceBookPinStore()

    let offlineSync: OfflineSyncManager

    let appearance = AppearanceSettings()



    @Published var selectedTab: MainTab = .dashboard

    @Published var paymentReturn: PaymentReturn?

    @Published var pendingInboxConversationId: String?

    @Published var pendingInboxCustomer: InboxCustomerNavigation?

    @Published var pendingVisitId: String?

    @Published var pendingCustomerId: String?

    @Published var pendingEstimateId: String?

    @Published var pendingDeepLink: String?

    @Published var deepLinkNavigation: DeepLinkNavigation?



    init(modelContainer: ModelContainer) {

        let tokenStore = TokenStore()

        let apiClient = APIClient(tokenStore: tokenStore)

        self.tokenStore = tokenStore

        self.apiClient = apiClient

        self.auth = AuthManager(tokenStore: tokenStore, apiClient: apiClient)

        self.branding = CompanyBranding()

        self.voice = VoiceManager(apiClient: apiClient, auth: self.auth)

        self.offlineSync = OfflineSyncManager(modelContainer: modelContainer)

    }



    func bootstrapAfterLogin() {

        offlineSync.configure(apiClient: apiClient)

    }



    func applyPushNavigation(from push: PushNotificationManager) {

        if let conversationId = push.pendingConversationId {

            pendingInboxConversationId = conversationId

            selectedTab = .messages

        }

        if let visitId = push.pendingVisitId {

            pendingVisitId = visitId

            deepLinkNavigation = .visit(visitId)

            selectedTab = .schedule

        }

        if let customerId = push.pendingCustomerId {

            pendingCustomerId = customerId

            deepLinkNavigation = .customer(customerId)

            selectedTab = .customers

        }

        if let estimateId = push.pendingEstimateId {

            pendingEstimateId = estimateId

            deepLinkNavigation = .estimate(estimateId)

            selectedTab = .schedule

        }

        if let deepLink = push.pendingDeepLink {

            pendingDeepLink = deepLink

            if let url = URL(string: deepLink) {

                handleDeepLink(url)

            }

        }

        push.clearPendingNavigation()

    }



    func handleDeepLink(_ url: URL) {

        guard url.scheme == "stormcrm" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        if url.host == "payment-return" {

            let visitId = components?.queryItems?.first(where: { $0.name == "visitId" })?.value

            let sessionId = components?.queryItems?.first(where: { $0.name == "session_id" })?.value

            let cancelled = components?.queryItems?.contains(where: { $0.name == "payment" && $0.value == "cancelled" }) == true

            if let visitId {

                paymentReturn = PaymentReturn(visitId: visitId, sessionId: sessionId, cancelled: cancelled)

            }

        } else if url.host == "inbox" {

            selectedTab = .messages

            if let conversationId = components?.queryItems?.first(where: { $0.name == "conversationId" })?.value {

                pendingInboxConversationId = conversationId

            }

        } else if url.host == "visit" {
            let pathId = url.path.split(separator: "/").map(String.init).first(where: { !$0.isEmpty })
            if let visitId = components?.queryItems?.first(where: { $0.name == "id" })?.value
                ?? pathId
            {
                pendingVisitId = visitId
                deepLinkNavigation = .visit(visitId)
                selectedTab = .schedule
            }
        } else if url.host == "customer" {
            let pathId = url.path.split(separator: "/").map(String.init).first(where: { !$0.isEmpty })
            if let customerId = components?.queryItems?.first(where: { $0.name == "id" })?.value
                ?? pathId
            {
                pendingCustomerId = customerId
                deepLinkNavigation = .customer(customerId)
                selectedTab = .customers
            }
        } else if url.host == "conversation" {
            let pathId = url.path.split(separator: "/").map(String.init).first(where: { !$0.isEmpty })
            if let conversationId = components?.queryItems?.first(where: { $0.name == "id" })?.value
                ?? pathId
            {
                pendingInboxConversationId = conversationId
                selectedTab = .messages
            }
        } else if url.host == "estimate" {
            let pathId = url.path.split(separator: "/").map(String.init).first(where: { !$0.isEmpty })
            if let estimateId = components?.queryItems?.first(where: { $0.name == "id" })?.value
                ?? pathId
            {
                pendingEstimateId = estimateId
                deepLinkNavigation = .estimate(estimateId)
                selectedTab = .schedule
            }
        } else if url.host == "sync" {

            selectedTab = .more

        } else if url.host == "dashboard" {

            selectedTab = .dashboard

        }

    }



    func openCustomerSmsInbox(customerId: String, name: String, phone: String?) {

        selectedTab = .messages

        Task {

            var query: [URLQueryItem] = [URLQueryItem(name: "customerId", value: customerId)]

            if let phone, !phone.isEmpty {

                query.append(URLQueryItem(name: "phone", value: phone))

            }



            if let response: ResolveConversationResponse = try? await apiClient.get(

                path: APIPath.smsConversationResolve,

                query: query

            ), let conversationId = response.conversation?.id {

                pendingInboxConversationId = conversationId

            } else {

                pendingInboxCustomer = InboxCustomerNavigation(

                    customerId: customerId,

                    name: name,

                    phone: phone

                )

            }

        }

    }

}



struct PaymentReturn: Identifiable {

    let id = UUID()

    let visitId: String

    let sessionId: String?

    let cancelled: Bool

}



struct ResolveConversationResponse: Decodable {

    let conversation: ConversationDTO?

}

