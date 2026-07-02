import Foundation
import SwiftUI

enum MainTab: Hashable {
    case dashboard
    case schedule
    case visits
    case customers
    case reporting
    case inbox
    case more
}

struct InboxCustomerNavigation: Hashable, Identifiable {
    let customerId: String
    let name: String
    let phone: String?

    var id: String { customerId }
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

    @Published var selectedTab: MainTab = .dashboard
    @Published var paymentReturn: PaymentReturn?
    @Published var pendingInboxConversationId: String?
    @Published var pendingInboxCustomer: InboxCustomerNavigation?

    init() {
        let tokenStore = TokenStore()
        let apiClient = APIClient(tokenStore: tokenStore)
        self.tokenStore = tokenStore
        self.apiClient = apiClient
        self.auth = AuthManager(tokenStore: tokenStore, apiClient: apiClient)
        self.branding = CompanyBranding()
        self.voice = VoiceManager(apiClient: apiClient, auth: self.auth)
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
            selectedTab = .inbox
            if let conversationId = components?.queryItems?.first(where: { $0.name == "conversationId" })?.value {
                pendingInboxConversationId = conversationId
            }
        }
    }

    func openCustomerSmsInbox(customerId: String, name: String, phone: String?) {
        selectedTab = .inbox
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
