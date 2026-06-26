import Foundation

/// Twilio Voice integration.
/// Add the Twilio Voice iOS SDK via Swift Package Manager:
/// https://github.com/twilio/twilio-voice-ios
///
/// When the SDK is linked, uncomment the Twilio imports and implement connect/call.
@MainActor
final class VoiceManager: ObservableObject {
    @Published var status = "Ready"
    @Published var lastError: String?

    private let apiClient: APIClient
    private var cachedToken: String?

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func prepare() async {
        do {
            struct TokenResponse: Decodable {
                let token: String
                let identity: String
            }
            let response: TokenResponse = try await apiClient.post(path: APIPath.voiceToken)
            cachedToken = response.token
            status = "Voice ready"
        } catch {
            lastError = (error as? APIError)?.message ?? error.localizedDescription
            status = "Voice unavailable"
        }
    }

    func call(phone: String) async {
        if cachedToken == nil {
            await prepare()
        }
        struct Body: Encodable {
            let to: String
        }
        do {
            struct CallResponse: Decodable { let sid: String? }
            let _: CallResponse = try await apiClient.post(path: APIPath.voiceCall, body: Body(to: phone))
            status = "Calling \(phone)…"
            #if canImport(UIKit)
            if let url = URL(string: "tel:\(phone)") {
                await UIApplication.shared.open(url)
            }
            #endif
        } catch {
            lastError = (error as? APIError)?.message ?? error.localizedDescription
            #if canImport(UIKit)
            if let url = URL(string: "tel:\(phone)") {
                await UIApplication.shared.open(url)
            }
            #endif
        }
    }
}

#if canImport(UIKit)
import UIKit
#endif
