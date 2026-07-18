import CryptoKit
import Foundation
import Security
import SwiftData

enum OutboxMutationStatus: String, Codable {
    case pending
    case syncing
    case failed
}

@Model
final class CachedVisit {
    @Attribute(.unique) var id: String
    var jsonData: Data
    var startAt: Date
    var syncedAt: Date

    init(id: String, jsonData: Data, startAt: Date, syncedAt: Date = Date()) {
        self.id = id
        self.jsonData = jsonData
        self.startAt = startAt
        self.syncedAt = syncedAt
    }
}

@Model
final class CachedCustomer {
    @Attribute(.unique) var id: String
    var jsonData: Data
    var name: String
    var syncedAt: Date

    init(id: String, jsonData: Data, name: String, syncedAt: Date = Date()) {
        self.id = id
        self.jsonData = jsonData
        self.name = name
        self.syncedAt = syncedAt
    }
}

@Model
final class CachedProperty {
    @Attribute(.unique) var id: String
    var customerId: String
    var jsonData: Data
    var syncedAt: Date

    init(id: String, customerId: String, jsonData: Data, syncedAt: Date = Date()) {
        self.id = id
        self.customerId = customerId
        self.jsonData = jsonData
        self.syncedAt = syncedAt
    }
}

@Model
final class OutboxMutation {
    @Attribute(.unique) var id: String
    var path: String
    var method: String
    var bodyData: Data?
    /// When true, `bodyData` is ChaChaPoly-sealed (Keychain-backed key).
    var bodyEncrypted: Bool
    /// Optional visit id for UI / pending-payment checks without decrypting the body.
    var relatedVisitId: String?
    var createdAt: Date
    var retryCount: Int
    var idempotencyKey: String
    var status: String
    var lastError: String?

    init(
        id: String = UUID().uuidString,
        path: String,
        method: String,
        bodyData: Data? = nil,
        bodyEncrypted: Bool = false,
        relatedVisitId: String? = nil,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        idempotencyKey: String = UUID().uuidString,
        status: String = OutboxMutationStatus.pending.rawValue,
        lastError: String? = nil
    ) {
        self.id = id
        self.path = path
        self.method = method
        self.bodyData = bodyData
        self.bodyEncrypted = bodyEncrypted
        self.relatedVisitId = relatedVisitId
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.idempotencyKey = idempotencyKey
        self.status = status
        self.lastError = lastError
    }
}

enum PIIProtection {
    private static let keychainAccount = "stormcrm.offline.pii.key"

    static func encrypt(_ plaintext: String) -> Data? {
        guard let data = plaintext.data(using: .utf8) else { return nil }
        return encryptData(data)
    }

    static func decrypt(_ sealed: Data) -> String? {
        guard let data = decryptData(sealed) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func encryptData(_ plaintext: Data) -> Data? {
        guard let key = symmetricKey() else { return nil }
        return try? ChaChaPoly.seal(plaintext, using: key).combined
    }

    static func decryptData(_ sealed: Data) -> Data? {
        guard let key = symmetricKey(),
              let box = try? ChaChaPoly.SealedBox(combined: sealed),
              let data = try? ChaChaPoly.open(box, using: key)
        else { return nil }
        return data
    }

    private static func symmetricKey() -> SymmetricKey? {
        if let existing = loadKey() {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        saveKey(key)
        return key
    }

    private static func loadKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func saveKey(_ key: SymmetricKey) {
        let data = key.withUnsafeBytes { Data($0) }
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
        ] as CFDictionary)
        SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ] as CFDictionary, nil)
    }
}
