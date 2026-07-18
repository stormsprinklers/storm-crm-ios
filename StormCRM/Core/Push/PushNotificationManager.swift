import Foundation
import UIKit
import UserNotifications

enum PushNotificationCategory: String, CaseIterable {
    case jobAssigned = "JOB_ASSIGNED"
    case scheduleChanged = "SCHEDULE_CHANGED"
    case inboxSms = "INBOX_SMS"
    case missedTransfer = "MISSED_TRANSFER"
    case estimateApproved = "ESTIMATE_APPROVED"
    case paymentReceived = "PAYMENT_RECEIVED"
    case timerLeftRunning = "TIMER_LEFT_RUNNING"
    case syncFailed = "SYNC_FAILED"

    var identifier: String { rawValue }
}

@MainActor
final class PushNotificationManager: ObservableObject {
    static let shared = PushNotificationManager()

    @Published var pendingConversationId: String?
    @Published var pendingVisitId: String?
    @Published var pendingCustomerId: String?
    @Published var pendingEstimateId: String?
    @Published var pendingDeepLink: String?

    private(set) var deviceToken: String?
    private var authorizationRequested = false

    static func registerCategories() {
        let categories = PushNotificationCategory.allCases.map { category in
            UNNotificationCategory(identifier: category.identifier, actions: [], intentIdentifiers: [], options: [])
        }
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories))
    }

    func requestAuthorizationIfNeeded() async {
        guard !authorizationRequested else { return }
        authorizationRequested = true

        Self.registerCategories()
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
        if let conversationId = stringValue(userInfo["conversationId"]), !conversationId.isEmpty {
            pendingConversationId = conversationId
        }
        if let visitId = stringValue(userInfo["visitId"]), !visitId.isEmpty {
            pendingVisitId = visitId
        }
        if let customerId = stringValue(userInfo["customerId"]), !customerId.isEmpty {
            pendingCustomerId = customerId
        }
        if let estimateId = stringValue(userInfo["estimateId"]), !estimateId.isEmpty {
            pendingEstimateId = estimateId
        }
        if let deepLink = stringValue(userInfo["deepLink"]), !deepLink.isEmpty {
            pendingDeepLink = deepLink
        }

        if pendingVisitId == nil,
           pendingCustomerId == nil,
           pendingEstimateId == nil,
           pendingConversationId == nil,
           pendingDeepLink == nil,
           let type = stringValue(userInfo["type"]) {
            routeByType(type, userInfo: userInfo)
        }
    }

    func clearPendingNavigation() {
        pendingConversationId = nil
        pendingVisitId = nil
        pendingCustomerId = nil
        pendingEstimateId = nil
        pendingDeepLink = nil
    }

    private func routeByType(_ type: String, userInfo: [AnyHashable: Any]) {
        switch type {
        case PushNotificationCategory.inboxSms.rawValue:
            if let conversationId = stringValue(userInfo["conversationId"]) {
                pendingConversationId = conversationId
            }
        case PushNotificationCategory.jobAssigned.rawValue,
             PushNotificationCategory.scheduleChanged.rawValue:
            if let visitId = stringValue(userInfo["visitId"]) {
                pendingVisitId = visitId
            }
        case PushNotificationCategory.estimateApproved.rawValue:
            if let estimateId = stringValue(userInfo["estimateId"]) {
                pendingEstimateId = estimateId
            }
        case PushNotificationCategory.paymentReceived.rawValue:
            if let visitId = stringValue(userInfo["visitId"]) {
                pendingVisitId = visitId
            }
        case PushNotificationCategory.missedTransfer.rawValue:
            pendingDeepLink = "stormcrm://inbox"
        case PushNotificationCategory.syncFailed.rawValue:
            pendingDeepLink = "stormcrm://sync"
        case PushNotificationCategory.timerLeftRunning.rawValue:
            pendingDeepLink = "stormcrm://dashboard"
        default:
            break
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}

extension Notification.Name {
    static let pushDeviceTokenUpdated = Notification.Name("stormcrm.pushDeviceTokenUpdated")
}
