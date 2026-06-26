import Foundation
import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {
    let tokenStore = TokenStore()
    lazy var apiClient = APIClient(tokenStore: tokenStore)
    lazy var auth = AuthManager(tokenStore: tokenStore, apiClient: apiClient)
    let location = LocationManager()
    lazy var voice = VoiceManager(apiClient: apiClient)

    @Published var paymentReturn: PaymentReturn?

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "stormcrm" else { return }
        if url.host == "payment-return" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let visitId = components?.queryItems?.first(where: { $0.name == "visitId" })?.value
            let sessionId = components?.queryItems?.first(where: { $0.name == "session_id" })?.value
            let cancelled = components?.queryItems?.contains(where: { $0.name == "payment" && $0.value == "cancelled" }) == true
            if let visitId {
                paymentReturn = PaymentReturn(visitId: visitId, sessionId: sessionId, cancelled: cancelled)
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
