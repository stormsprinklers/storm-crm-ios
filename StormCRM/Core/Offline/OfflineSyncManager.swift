import Combine
import Foundation
import Network
import SwiftData
import UserNotifications

@MainActor
final class OfflineSyncManager: ObservableObject {
    @Published private(set) var isOnline = true
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastError: String?
    @Published private(set) var isSyncing = false

    private let modelContainer: ModelContainer
    private var apiClient: APIClient?
    private var flushTask: Task<Void, Never>?
    private let maxRetries = 8
    private var openTimeSegment: TechTimeSegmentDTO?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        isOnline = NetworkReachability.shared.isOnline
        refreshPendingCount()
        NetworkReachability.shared.$isOnline
            .receive(on: DispatchQueue.main)
            .sink { [weak self] online in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = online
                if online && wasOffline {
                    self.flushOutbox()
                }
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    func configure(apiClient: APIClient) {
        self.apiClient = apiClient
        MediaUploadQueue.shared.configure(apiClient: apiClient)
        if isOnline {
            flushOutbox()
        }
    }

    func updateOpenTimeSegment(_ segment: TechTimeSegmentDTO?) {
        openTimeSegment = segment
    }

    func enqueue(
        path: String,
        method: String,
        bodyData: Data?,
        secure: Bool = false,
        relatedVisitId: String? = nil,
        idempotencyKey: String = UUID().uuidString
    ) {
        var storedBody = bodyData
        var encrypted = false
        if secure, let bodyData {
            if let sealed = PIIProtection.encryptData(bodyData) {
                storedBody = sealed
                encrypted = true
            }
            // If encryption fails, still queue plaintext rather than drop the payment.
        }
        let context = OfflineStore.sharedContext(from: modelContainer)
        context.insert(
            OutboxMutation(
                path: path,
                method: method.uppercased(),
                bodyData: storedBody,
                bodyEncrypted: encrypted,
                relatedVisitId: relatedVisitId,
                idempotencyKey: idempotencyKey
            )
        )
        try? context.save()
        refreshPendingCount()
        if isOnline {
            flushOutbox()
        }
    }

    /// True when a cash/check (or other payment) mutation for this visit is waiting to sync.
    func hasPendingPayment(forVisitId visitId: String) -> Bool {
        pendingMutations().contains { mutation in
            guard mutation.relatedVisitId == visitId else { return false }
            let status = mutation.status
            guard status == OutboxMutationStatus.pending.rawValue
                || status == OutboxMutationStatus.failed.rawValue
                || status == OutboxMutationStatus.syncing.rawValue
            else { return false }
            return mutation.path == APIPath.paymentsManual
                || mutation.path.hasSuffix("/invoice")
        }
    }

    func pendingPaymentMethodLabel(forVisitId visitId: String) -> String? {
        let mutation = pendingMutations().first {
            $0.relatedVisitId == visitId && $0.path == APIPath.paymentsManual
        }
        guard let mutation else { return nil }
        guard let plain = plaintextBody(for: mutation),
              let json = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let method = json["method"] as? String
        else {
            return "Payment"
        }
        return method == "CHECK" ? "Check" : "Cash"
    }

    func retryMutation(id: String) {
        let context = OfflineStore.sharedContext(from: modelContainer)
        var descriptor = FetchDescriptor<OutboxMutation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let mutation = try? context.fetch(descriptor).first else { return }
        mutation.status = OutboxMutationStatus.pending.rawValue
        mutation.lastError = nil
        try? context.save()
        refreshPendingCount()
        flushOutbox()
    }

    func deleteMutation(id: String) {
        let context = OfflineStore.sharedContext(from: modelContainer)
        var descriptor = FetchDescriptor<OutboxMutation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let mutation = try? context.fetch(descriptor).first {
            context.delete(mutation)
            try? context.save()
        }
        refreshPendingCount()
    }

    func cacheVisits(_ visits: [VisitDTO]) {
        let context = OfflineStore.sharedContext(from: modelContainer)
        OfflineCacheBootstrap.upsertVisits(visits, context: context)
    }

    func cachedVisit(id: String) -> VisitDTO? {
        let context = OfflineStore.sharedContext(from: modelContainer)
        return OfflineCacheBootstrap.cachedVisit(id: id, context: context)
    }

    func pendingMutations() -> [OutboxMutation] {
        let context = OfflineStore.sharedContext(from: modelContainer)
        let descriptor = FetchDescriptor<OutboxMutation>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func flushOutbox() {
        guard flushTask == nil, isOnline, apiClient != nil else { return }
        flushTask = Task { [weak self] in
            await self?.performFlush()
            await MainActor.run { self?.flushTask = nil }
        }
    }

    func handleAppBackgrounded(apiClient: APIClient? = nil) {
        if openTimeSegment == nil, let apiClient {
            Task {
                let dashboard: MobileDashboardDTO? = try? await apiClient.get(path: APIPath.mobileDashboard)
                openTimeSegment = dashboard?.openSegment
                TimerRunningNotificationHelper.scheduleIfNeeded(segment: openTimeSegment)
            }
            return
        }
        TimerRunningNotificationHelper.scheduleIfNeeded(segment: openTimeSegment)
    }

    func handleAppForegrounded() {
        TimerRunningNotificationHelper.cancelScheduledReminder()
    }

    private func performFlush() async {
        guard let apiClient else { return }
        isSyncing = true
        defer {
            isSyncing = false
            refreshPendingCount()
        }

        while !Task.isCancelled {
            let context = OfflineStore.sharedContext(from: modelContainer)
            let pendingStatus = OutboxMutationStatus.pending.rawValue
            let failedStatus = OutboxMutationStatus.failed.rawValue
            var descriptor = FetchDescriptor<OutboxMutation>(
                predicate: #Predicate {
                    $0.status == pendingStatus || $0.status == failedStatus
                },
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )
            descriptor.fetchLimit = 1
            guard let mutation = try? context.fetch(descriptor).first else { break }
            if mutation.retryCount >= maxRetries {
                mutation.status = OutboxMutationStatus.failed.rawValue
                try? context.save()
                continue
            }

            mutation.status = OutboxMutationStatus.syncing.rawValue
            try? context.save()

            do {
                try await sendMutation(mutation, api: apiClient)
                let visitId = mutation.relatedVisitId
                let path = mutation.path
                context.delete(mutation)
                try? context.save()
                lastError = nil
                if let visitId, path == APIPath.paymentsManual || path.hasSuffix("/invoice") {
                    NotificationCenter.default.post(
                        name: .visitPaymentCompleted,
                        object: nil,
                        userInfo: ["visitId": visitId]
                    )
                }
            } catch {
                mutation.retryCount += 1
                mutation.status = mutation.retryCount >= maxRetries
                    ? OutboxMutationStatus.failed.rawValue
                    : OutboxMutationStatus.pending.rawValue
                mutation.lastError = (error as? APIError)?.message ?? error.localizedDescription
                lastError = mutation.lastError
                try? context.save()
                if !isOnline { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        refreshPendingCount()
    }

    private func sendMutation(_ mutation: OutboxMutation, api: APIClient) async throws {
        let headers = ["Idempotency-Key": mutation.idempotencyKey]
        switch mutation.method {
        case "POST":
            if mutation.bodyData != nil {
                guard let bodyData = plaintextBody(for: mutation) else {
                    throw APIError.server("Could not decrypt offline payload")
                }
                let _: EmptyResponse = try await postRaw(
                    path: mutation.path,
                    bodyData: bodyData,
                    headers: headers,
                    api: api
                )
            } else {
                let _: EmptyResponse = try await api.post(path: mutation.path, headers: headers)
            }
        case "PATCH":
            guard let bodyData = plaintextBody(for: mutation) else {
                throw APIError.badRequest(
                    mutation.bodyEncrypted ? "Could not decrypt offline payload" : "Missing PATCH body"
                )
            }
            let _: EmptyResponse = try await patchRaw(
                path: mutation.path,
                bodyData: bodyData,
                headers: headers,
                api: api
            )
        case "PUT":
            if mutation.bodyData != nil {
                guard let bodyData = plaintextBody(for: mutation) else {
                    throw APIError.server("Could not decrypt offline payload")
                }
                let _: EmptyResponse = try await putRaw(
                    path: mutation.path,
                    bodyData: bodyData,
                    headers: headers,
                    api: api
                )
            } else {
                let _: EmptyResponse = try await api.put(path: mutation.path, headers: headers)
            }
        case "DELETE":
            try await api.delete(path: mutation.path)
        default:
            throw APIError.server("Unsupported method \(mutation.method)")
        }
    }

    private func plaintextBody(for mutation: OutboxMutation) -> Data? {
        guard let bodyData = mutation.bodyData else { return nil }
        if mutation.bodyEncrypted {
            guard let plain = PIIProtection.decryptData(bodyData) else {
                return nil
            }
            return plain
        }
        return bodyData
    }

    private func postRaw(
        path: String,
        bodyData: Data,
        headers: [String: String],
        api: APIClient
    ) async throws -> EmptyResponse {
        let value = try JSONDecoder().decode(AnyCodableValue.self, from: bodyData)
        return try await api.post(path: path, body: value, headers: headers)
    }

    private func patchRaw(
        path: String,
        bodyData: Data,
        headers: [String: String],
        api: APIClient
    ) async throws -> EmptyResponse {
        let value = try JSONDecoder().decode(AnyCodableValue.self, from: bodyData)
        return try await api.patch(path: path, body: value, headers: headers)
    }

    private func putRaw(
        path: String,
        bodyData: Data,
        headers: [String: String],
        api: APIClient
    ) async throws -> EmptyResponse {
        let value = try JSONDecoder().decode(AnyCodableValue.self, from: bodyData)
        return try await api.put(path: path, body: value, headers: headers)
    }

    private func refreshPendingCount() {
        let context = OfflineStore.sharedContext(from: modelContainer)
        let pendingStatus = OutboxMutationStatus.pending.rawValue
        let failedStatus = OutboxMutationStatus.failed.rawValue
        let descriptor = FetchDescriptor<OutboxMutation>(
            predicate: #Predicate { $0.status == pendingStatus || $0.status == failedStatus }
        )
        pendingCount = (try? context.fetchCount(descriptor)) ?? 0
    }
}

private struct AnyCodableValue: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let number = try? container.decode(Double.self) {
            value = number
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodableValue].self) {
            value = array.map { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let string as String: try container.encode(string)
        case let bool as Bool: try container.encode(bool)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodableValue($0) })
        case let array as [Any]:
            try container.encode(array.map { AnyCodableValue($0) })
        default:
            try container.encodeNil()
        }
    }
}

enum TimerRunningNotificationHelper {
    static let requestId = "stormcrm.timer-left-running"

    static func scheduleIfNeeded(segment: TechTimeSegmentDTO?) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestId])
        guard let segment else { return }

        let content = UNMutableNotificationContent()
        content.title = "Timer still running"
        let categoryTitle = TechTimeCategory(rawValue: segment.category)?.title ?? segment.category
        content.body = "Your \(categoryTitle.lowercased()) timer has been running since \(APIDateFormatting.displayString(from: segment.startedAt))."
        content.categoryIdentifier = PushNotificationCategory.timerLeftRunning.rawValue
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)
        center.add(request)
    }

    static func cancelScheduledReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestId])
    }
}
