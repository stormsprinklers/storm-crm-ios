import Foundation
import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {
    let tokenStore: TokenStore
    let apiClient: APIClient
    let auth: AuthManager
    let branding: CompanyBranding
    let location = LocationManager()
    let voice: VoiceManager

    @Published var paymentReturn: PaymentReturn?
    @Published var pendingInboxConversationId: String?

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
            if let conversationId = components?.queryItems?.first(where: { $0.name == "conversationId" })?.value {
                pendingInboxConversationId = conversationId
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
