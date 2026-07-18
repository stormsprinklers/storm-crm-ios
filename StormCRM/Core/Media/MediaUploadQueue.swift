import Foundation
import Network
import SwiftUI
import UIKit

enum MediaUploadTarget: Codable, Equatable {
    case visitAttachment(visitId: String)
    case customerAttachment(customerId: String)
    case inboxMedia
}

enum MediaUploadStatus: String, Codable {
    case pending
    case uploading
    case failed
    case completed
}

struct PendingMediaUpload: Codable, Identifiable, Equatable {
    let id: UUID
    let target: MediaUploadTarget
    let apiPath: String
    let fileName: String
    let mimeType: String
    let localFileName: String
    var retryCount: Int
    var lastError: String?
    var status: MediaUploadStatus
    let createdAt: Date

    init(
        id: UUID = UUID(),
        target: MediaUploadTarget,
        apiPath: String,
        fileName: String,
        mimeType: String,
        localFileName: String,
        retryCount: Int = 0,
        lastError: String? = nil,
        status: MediaUploadStatus = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.target = target
        self.apiPath = apiPath
        self.fileName = fileName
        self.mimeType = mimeType
        self.localFileName = localFileName
        self.retryCount = retryCount
        self.lastError = lastError
        self.status = status
        self.createdAt = createdAt
    }
}

@MainActor
final class MediaUploadQueue: ObservableObject {
    static let shared = MediaUploadQueue()

    @Published private(set) var items: [PendingMediaUpload] = []
    @Published private(set) var isProcessing = false

    private var apiClient: APIClient?
    private var processTask: Task<Void, Never>?
    private let maxRetries = 5

    private var queueDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("PendingUploads", isDirectory: true)
    }

    private var manifestURL: URL {
        queueDirectory.appendingPathComponent("manifest.json")
    }

    private init() {
        loadManifest()
    }

    func configure(apiClient: APIClient) {
        self.apiClient = apiClient
        kickProcessLoop()
    }

    func enqueueVisitPhoto(visitId: String, data: Data, fileName: String, mimeType: String = "image/jpeg") throws {
        try enqueue(
            target: .visitAttachment(visitId: visitId),
            apiPath: APIPath.visitAttachments(visitId),
            data: data,
            fileName: fileName,
            mimeType: mimeType
        )
    }

    func enqueueCustomerPhoto(customerId: String, data: Data, fileName: String, mimeType: String = "image/jpeg") throws {
        try enqueue(
            target: .customerAttachment(customerId: customerId),
            apiPath: APIPath.customerAttachments(customerId),
            data: data,
            fileName: fileName,
            mimeType: mimeType
        )
    }

    func enqueueInboxMedia(data: Data, fileName: String, mimeType: String) throws {
        try enqueue(
            target: .inboxMedia,
            apiPath: APIPath.inboxMediaUpload,
            data: data,
            fileName: fileName,
            mimeType: mimeType
        )
    }

    func retry(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .pending
        items[index].lastError = nil
        saveManifest()
        kickProcessLoop()
    }

    func remove(id: UUID) {
        if let item = items.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: localFileURL(for: item))
        }
        items.removeAll { $0.id == id }
        saveManifest()
    }

    func pendingCount(for visitId: String? = nil) -> Int {
        items.filter { item in
            guard item.status == .pending || item.status == .failed || item.status == .uploading else { return false }
            if let visitId {
                if case .visitAttachment(let id) = item.target {
                    return id == visitId
                }
                return false
            }
            return true
        }.count
    }

    func pendingCount(forCustomerId customerId: String) -> Int {
        items.filter { item in
            guard item.status == .pending || item.status == .failed || item.status == .uploading else { return false }
            if case .customerAttachment(let id) = item.target {
                return id == customerId
            }
            return false
        }.count
    }

    private func enqueue(
        target: MediaUploadTarget,
        apiPath: String,
        data: Data,
        fileName: String,
        mimeType: String
    ) throws {
        try FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        let localFileName = "\(UUID().uuidString)-\(fileName)"
        let fileURL = queueDirectory.appendingPathComponent(localFileName)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])

        let item = PendingMediaUpload(
            target: target,
            apiPath: apiPath,
            fileName: fileName,
            mimeType: mimeType,
            localFileName: localFileName
        )
        items.append(item)
        saveManifest()
        kickProcessLoop()
    }

    private func kickProcessLoop() {
        guard processTask == nil else { return }
        processTask = Task { [weak self] in
            await self?.processUntilIdle()
            await MainActor.run { self?.processTask = nil }
        }
    }

    private func processUntilIdle() async {
        guard let apiClient else { return }
        isProcessing = true
        defer { isProcessing = false }

        while !Task.isCancelled {
            guard let index = items.firstIndex(where: { $0.status == .pending || ($0.status == .failed && $0.retryCount < maxRetries) }) else {
                break
            }

            var item = items[index]
            item.status = .uploading
            items[index] = item
            saveManifest()

            let fileURL = localFileURL(for: item)
            guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
                item.status = .failed
                item.lastError = "Missing local file"
                items[index] = item
                saveManifest()
                continue
            }

            do {
                _ = try await apiClient.uploadMultipart(
                    path: item.apiPath,
                    fileData: data,
                    fileName: item.fileName,
                    mimeType: item.mimeType
                ) as Data
                try? FileManager.default.removeItem(at: fileURL)
                items.remove(at: index)
                saveManifest()
            } catch {
                item.retryCount += 1
                item.status = item.retryCount >= maxRetries ? .failed : .pending
                item.lastError = (error as? APIError)?.message ?? error.localizedDescription
                items[index] = item
                saveManifest()
                if !NetworkReachability.shared.isOnline {
                    break
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func localFileURL(for item: PendingMediaUpload) -> URL {
        queueDirectory.appendingPathComponent(item.localFileName)
    }

    private func loadManifest() {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return }
        do {
            let data = try Data(contentsOf: manifestURL)
            items = try JSONCoding.makeDecoder().decode([PendingMediaUpload].self, from: data)
        } catch {
            items = []
        }
    }

    private func saveManifest() {
        try? FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        if let data = try? JSONCoding.makeEncoder().encode(items) {
            try? data.write(to: manifestURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}

/// Shared reachability helper used by upload and offline sync.
@MainActor
final class NetworkReachability: ObservableObject {
    static let shared = NetworkReachability()

    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "stormcrm.network")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}
