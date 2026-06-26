import Foundation

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var user: UserDTO?
    @Published private(set) var isAuthenticated = false
    @Published var lastError: String?

    private let tokenStore: TokenStore
    private let apiClient: APIClient

    init(tokenStore: TokenStore, apiClient: APIClient) {
        self.tokenStore = tokenStore
        self.apiClient = apiClient
        if tokenStore.tokens != nil {
            isAuthenticated = true
        }
    }

    func login(email: String, password: String) async {
        lastError = nil
        do {
            let body = LoginRequest(
                email: email,
                password: password,
                deviceName: UIDevice.current.name
            )
            let response: LoginResponse = try await apiClient.post(
                path: APIPath.mobileLogin,
                body: body,
                authenticated: false
            )
            tokenStore.save(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresIn: response.expiresIn
            )
            user = response.user
            isAuthenticated = true
        } catch {
            lastError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func logout() async {
        if let refresh = tokenStore.tokens?.refreshToken {
            _ = try? await apiClient.post(
                path: APIPath.mobileLogout,
                body: LogoutRequest(refreshToken: refresh),
                authenticated: true
            ) as EmptyResponse
        }
        tokenStore.clear()
        user = nil
        isAuthenticated = false
    }

    func refreshIfNeeded() async throws {
        guard tokenStore.isAccessTokenExpiringSoon() else { return }
        guard let refreshToken = tokenStore.tokens?.refreshToken else {
            throw APIError.unauthorized
        }
        let response: LoginResponse = try await apiClient.post(
            path: APIPath.mobileRefresh,
            body: RefreshRequest(refreshToken: refreshToken),
            authenticated: false
        )
        tokenStore.save(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresIn: response.expiresIn
        )
        user = response.user
        isAuthenticated = true
    }
}

#if canImport(UIKit)
import UIKit
#endif

struct LoginRequest: Encodable {
    let email: String
    let password: String
    let deviceName: String
}

struct RefreshRequest: Encodable {
    let refreshToken: String
}

struct LogoutRequest: Encodable {
    let refreshToken: String
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
