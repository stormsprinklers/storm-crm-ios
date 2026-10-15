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

    private(set) var deviceToken: String? = UserDefaults.standard.string(forKey: "stormcrm.apnsDeviceToken")
    @Published private(set) var permissionStatus = "Checking…"
    @Published private(set) var registrationStatus = "Not registered"
    @Published private(set) var serverConfigured: Bool?
    @Published var lastError: String?
    @Published var testResult: String?

    static func registerCategories() {
        let categories = PushNotificationCategory.allCases.map { category in
            UNNotificationCategory(identifier: category.identifier, actions: [], intentIdentifiers: [], options: [])
        }
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories))
    }

    func requestAuthorizationIfNeeded() async {
        Self.registerCategories()
        let center = UNUserNotificationCenter.current()
        do {
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                settings = await center.notificationSettings()
            }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                permissionStatus = settings.authorizationStatus == .provisional ? "Quiet delivery" : "Allowed"
                UIApplication.shared.registerForRemoteNotifications()
            case .denied: permissionStatus = "Disabled in iPhone Settings"
            default: permissionStatus = "Not enabled"
            }
        } catch { lastError = error.localizedDescription }
    }

    func setDeviceToken(_ data: Data) {
        deviceToken = data.map { String(format: "%02.2hhx", $0) }.joined()
        UserDefaults.standard.set(deviceToken, forKey: "stormcrm.apnsDeviceToken")
        NotificationCenter.default.post(name: .pushDeviceTokenUpdated, object: nil)
    }

    func syncToken(api: APIClient) async {
        guard let deviceToken, !deviceToken.isEmpty else { return }
        struct Body: Encodable {
            let deviceToken: String
            let platform: String
            let bundleId: String
        }
        do {
            let _: EmptyResponse = try await api.post(
                path: APIPath.mobilePushRegister,
                body: Body(
                    deviceToken: deviceToken,
                    platform: "ios",
                    bundleId: Bundle.main.bundleIdentifier ?? "com.stormsprinklers.stormcrm"
                )
            )
            registrationStatus = "This iPhone registered"
            lastError = nil
            await checkServer(api: api)
        } catch {
            registrationStatus = "Registration needs retry"
            lastError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func checkServer(api: APIClient) async {
        struct Status: Decodable { let configured: Bool; let registeredDevices: Int }
        do {
            let status: Status = try await api.get(path: "/api/mobile/push/status")
            serverConfigured = status.configured
            if status.registeredDevices == 0 { registrationStatus = "Not registered for this company" }
        } catch { lastError = (error as? APIError)?.message ?? error.localizedDescription }
    }

    func sendTest(api: APIClient) async {
        testResult = nil
        await requestAuthorizationIfNeeded()
        await syncToken(api: api)
        guard let deviceToken else { lastError = "This iPhone has not received a push token yet."; return }
        do {
            let _: EmptyResponse = try await api.post(path: "/api/mobile/push/status", body: ["deviceToken": deviceToken])
            testResult = "Test sent. Check your notification banner."
        } catch { lastError = (error as? APIError)?.message ?? error.localizedDescription }
    }

    func registrationFailed(_ error: Error) {
        registrationStatus = "Apple registration failed"
        lastError = error.localizedDescription
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
        // APNs tokens belong to the phone/app, not to a company login. Keep the
        // token so it can be registered immediately after switching or signing in.
        registrationStatus = "Not registered"
        serverConfigured = nil
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
