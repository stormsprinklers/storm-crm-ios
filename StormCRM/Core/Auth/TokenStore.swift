import Foundation
import Security

struct AuthTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

final class TokenStore {
    private let service = "com.stormsprinklers.stormcrm.tokens"
    private let tokenAccount = "default"
    private let userAccount = "user-profile"

    var tokens: AuthTokens? {
        get {
            guard let data = readKeychain(account: tokenAccount) else { return nil }
            return try? JSONDecoder().decode(AuthTokens.self, from: data)
        }
        set {
            if let newValue {
                let data = try? JSONEncoder().encode(newValue)
                if let data { writeKeychain(data, account: tokenAccount) }
            } else {
                deleteKeychain(account: tokenAccount)
            }
        }
    }

    /// Cached profile data belongs in Keychain, not unencrypted UserDefaults.
    var userData: Data? {
        get { readKeychain(account: userAccount) }
        set {
            if let newValue { writeKeychain(newValue, account: userAccount) }
            else { deleteKeychain(account: userAccount) }
        }
    }

    var accessToken: String? { tokens?.accessToken }

    func save(accessToken: String, refreshToken: String, expiresIn: Int) {
        tokens = AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }

    func clear() {
        tokens = nil
        userData = nil
    }

    func isAccessTokenExpiringSoon(leeway: TimeInterval = 60) -> Bool {
        guard let tokens else { return true }
        return tokens.expiresAt.timeIntervalSinceNow < leeway
    }

    private func readKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func writeKeychain(_ data: Data, account: String) {
        deleteKeychain(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
