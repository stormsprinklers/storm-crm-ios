import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationManager: ObservableObject {
    static let shared = PushNotificationManager()

    @Published var pendingConversationId: String?

    private(set) var deviceToken: String?
    private var authorizationRequested = false

    func requestAuthorizationIfNeeded() async {
        guard !authorizationRequested else { return }
        authorizationRequested = true

        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            print("Push authorization failed:", error.localizedDescription)
        }
    }

    func setDeviceToken(_ data: Data) {
        deviceToken = data.map { String(format: "%02.2hhx", $0) }.joined()
        NotificationCenter.default.post(name: .pushDeviceTokenUpdated, object: nil)
    }

    func syncToken(api: APIClient) async {
        guard let deviceToken, !deviceToken.isEmpty else { return }
        struct Body: Encodable {
            let deviceToken: String
            let platform: String
            let bundleId: String
        }
        _ = try? await api.post(
            path: APIPath.mobilePushRegister,
            body: Body(
                deviceToken: deviceToken,
                platform: "ios",
                bundleId: Bundle.main.bundleIdentifier ?? "com.stormsprinklers.stormcrm"
            )
        ) as EmptyResponse
    }

    func unregister(api: APIClient) async {
        guard let deviceToken, !deviceToken.isEmpty else { return }
        struct Body: Encodable {
            let deviceToken: String
        }
        _ = try? await api.post(
            path: APIPath.mobilePushUnregister,
            body: Body(deviceToken: deviceToken)
        ) as EmptyResponse
        self.deviceToken = nil
    }

    func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        if let conversationId = userInfo["conversationId"] as? String, !conversationId.isEmpty {
            pendingConversationId = conversationId
        }
    }
}

extension Notification.Name {
    static let pushDeviceTokenUpdated = Notification.Name("stormcrm.pushDeviceTokenUpdated")
}
