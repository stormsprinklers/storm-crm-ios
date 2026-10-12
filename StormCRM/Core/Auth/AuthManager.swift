import Foundation

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var user: UserDTO?
    @Published private(set) var isAuthenticated = false
    @Published var lastError: String?
    /// Set after password login when MFA is required.
    @Published private(set) var pendingMfa: PendingMfaChallenge?
    @Published private(set) var loginCompanies: [LoginCompanyChoice] = []
    @Published private(set) var isSwitchingCompany = false
    @Published var companySwitchError: String?

    private let tokenStore: TokenStore
    private let apiClient: APIClient

    init(tokenStore: TokenStore, apiClient: APIClient) {
        self.tokenStore = tokenStore
        self.apiClient = apiClient
        if let data = UserDefaults.standard.data(forKey: Self.userStorageKey),
           let saved = try? JSONDecoder().decode(UserDTO.self, from: data) {
            user = saved
        }
        if tokenStore.tokens != nil {
            isAuthenticated = true
        }
    }

    private static let userStorageKey = "stormcrm.user"

    private func persistUser(_ user: UserDTO?) {
        if let user, let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Self.userStorageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.userStorageKey)
        }
    }

    func login(email: String, password: String, companyId: String? = nil) async {
        lastError = nil
        pendingMfa = nil
        do {
            let body = LoginRequest(
                email: email,
                password: password,
                deviceName: UIDevice.current.name,
                companyId: companyId
            )
            let response: MobileLoginChallengeResponse = try await apiClient.post(
                path: APIPath.mobileLogin,
                body: body,
                authenticated: false
            )
            if response.needsCompanyChoice == true, let companies = response.companies {
                loginCompanies = companies
                return
            }
            loginCompanies = []
            if response.mfaRequired == true, let challengeId = response.challengeId {
                pendingMfa = PendingMfaChallenge(
                    challengeId: challengeId,
                    phoneMasked: response.destinationMasked ?? response.phoneMasked ?? "your phone",
                    channel: response.channel ?? "SMS",
                    debugCode: response.debugCode
                )
                return
            }
            // Legacy fallback if server ever returns tokens directly.
            if let access = response.accessToken,
               let refresh = response.refreshToken,
               let expiresIn = response.expiresIn,
               let user = response.user {
                applySession(accessToken: access, refreshToken: refresh, expiresIn: expiresIn, user: user)
            } else {
                lastError = "Unexpected login response"
            }
        } catch {
            lastError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func verifyMfa(code: String) async {
        guard let pending = pendingMfa else {
            lastError = "Sign in again."
            return
        }
        lastError = nil
        do {
            let body = MfaVerifyRequest(
                challengeId: pending.challengeId,
                code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                deviceName: UIDevice.current.name
            )
            let response: LoginResponse = try await apiClient.post(
                path: APIPath.mobileMfa,
                body: body,
                authenticated: false
            )
            pendingMfa = nil
            applySession(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresIn: response.expiresIn,
                user: response.user
            )
        } catch {
            lastError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func resendMfa(channel: String? = nil) async {
        guard let pending = pendingMfa else { return }
        lastError = nil
        do {
            let response: MfaResendResponse = try await apiClient.post(
                path: APIPath.mobileMfaResend,
                body: MfaResendRequest(
                    challengeId: pending.challengeId,
                    channel: channel ?? pending.channel
                ),
                authenticated: false
            )
            pendingMfa = PendingMfaChallenge(
                challengeId: response.challengeId,
                phoneMasked: response.destinationMasked ?? response.phoneMasked ?? pending.phoneMasked,
                channel: response.channel ?? channel ?? pending.channel,
                debugCode: response.debugCode
            )
        } catch {
            lastError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func cancelMfa() {
        pendingMfa = nil
        lastError = nil
        loginCompanies = []
    }

    func switchCompany(userId: String, prepare: () async throws -> Void) async throws {
        guard !isSwitchingCompany else { return }
        isSwitchingCompany = true
        apiClient.invalidateInFlightRequests()
        defer { isSwitchingCompany = false }
        let oldRefreshToken = tokenStore.tokens?.refreshToken
        try await prepare()
        let response: LoginResponse = try await apiClient.post(
            path: APIPath.mobileAccountSwitch,
            body: CompanySwitchRequest(userId: userId, deviceName: UIDevice.current.name)
        )
        apiClient.invalidateInFlightRequests()
        applySession(accessToken: response.accessToken, refreshToken: response.refreshToken,
                     expiresIn: response.expiresIn, user: response.user)
        if let oldRefreshToken {
            _ = try? await apiClient.post(path: APIPath.mobileLogout,
                body: LogoutRequest(refreshToken: oldRefreshToken)) as EmptyResponse
        }
    }

    private func applySession(
        accessToken: String,
        refreshToken: String,
        expiresIn: Int,
        user: UserDTO
    ) {
        tokenStore.save(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn
        )
        self.user = user
        persistUser(user)
        isAuthenticated = true
        Task {
            await PushNotificationManager.shared.requestAuthorizationIfNeeded()
            await PushNotificationManager.shared.syncToken(api: apiClient)
        }
    }

    func logout() async {
        #if canImport(TwilioVoice) && canImport(PushKit) && canImport(CallKit)
        await IncomingCallCoordinator.shared.stop()
        #endif
        _ = try? await apiClient.patch(
            path: APIPath.voicePresence,
            body: ["status": "OFFLINE"]
        ) as EmptyResponse
        await PushNotificationManager.shared.unregister(api: apiClient)
        if let refresh = tokenStore.tokens?.refreshToken {
            _ = try? await apiClient.post(
                path: APIPath.mobileLogout,
                body: LogoutRequest(refreshToken: refresh),
                authenticated: true
            ) as EmptyResponse
        }
        tokenStore.clear()
        user = nil
        persistUser(nil)
        pendingMfa = nil
        isAuthenticated = false
    }

    func refreshIfNeeded() async throws {
        guard tokenStore.isAccessTokenExpiringSoon() else { return }
        try await refreshSession()
    }

    func ensureUserLoaded() async throws {
        if user != nil { return }
        guard tokenStore.tokens != nil else {
            throw APIError.unauthorized
        }
        try await refreshSession()
    }

    /// Clears local auth when the server rejects the refresh token (no remote logout call).
    func handleSessionInvalidated() {
        tokenStore.clear()
        user = nil
        persistUser(nil)
        pendingMfa = nil
        isAuthenticated = false
    }

    private func refreshSession() async throws {
        do {
            let response = try await apiClient.refreshSessionTokens()
            user = response.user
            persistUser(response.user)
            isAuthenticated = true
        } catch {
            if tokenStore.tokens == nil {
                handleSessionInvalidated()
            }
            throw error
        }
    }
}

#if canImport(UIKit)
import UIKit
#endif

struct PendingMfaChallenge: Equatable {
    let challengeId: String
    let phoneMasked: String
    let channel: String
    let debugCode: String?
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
    let deviceName: String
    let companyId: String?
}

struct MfaVerifyRequest: Encodable {
    let challengeId: String
    let code: String
    let deviceName: String
}

struct MfaResendRequest: Encodable {
    let challengeId: String
    let channel: String?
}

struct MfaResendResponse: Decodable {
    let challengeId: String
    let phoneMasked: String?
    let destinationMasked: String?
    let channel: String?
    let debugCode: String?
}

struct RefreshRequest: Encodable {
    let refreshToken: String
}

struct LogoutRequest: Encodable {
    let refreshToken: String
}

struct MobileLoginChallengeResponse: Decodable {
    let needsCompanyChoice: Bool?
    let companies: [LoginCompanyChoice]?
    let mfaRequired: Bool?
    let challengeId: String?
    let phoneMasked: String?
    let destinationMasked: String?
    let channel: String?
    let debugCode: String?
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let user: UserDTO?
}

struct LoginResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: UserDTO
}

struct UserDTO: Codable, Identifiable {
    let id: String
    let email: String
    let name: String
    let companyId: String
    let role: String
}

struct EmptyResponse: Decodable {}

struct LoginCompanyChoice: Decodable, Identifiable {
    let companyId: String
    let companyName: String
    let userId: String
    var id: String { userId }
}

struct CompanySwitchRequest: Encodable {
    let userId: String
    let deviceName: String
}
