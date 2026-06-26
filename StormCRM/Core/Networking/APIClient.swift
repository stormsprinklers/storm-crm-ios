import Foundation

final class APIClient {
    private let tokenStore: TokenStore
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(tokenStore: TokenStore, session: URLSession = .shared) {
        self.tokenStore = tokenStore
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func get<T: Decodable>(
        path: String,
        query: [URLQueryItem] = [],
        authenticated: Bool = true
    ) async throws -> T {
        let request = try await buildRequest(path: path, method: "GET", query: query, authenticated: authenticated)
        return try await perform(request)
    }

    func post<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        authenticated: Bool = true
    ) async throws -> T {
        var request = try await buildRequest(path: path, method: "POST", authenticated: authenticated)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func post<T: Decodable>(
        path: String,
        authenticated: Bool = true
    ) async throws -> T {
        let request = try await buildRequest(path: path, method: "POST", authenticated: authenticated)
        return try await perform(request)
    }

    func patch<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        authenticated: Bool = true
    ) async throws -> T {
        var request = try await buildRequest(path: path, method: "PATCH", authenticated: authenticated)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func delete(path: String, query: [URLQueryItem] = [], authenticated: Bool = true) async throws {
        let request = try await buildRequest(path: path, method: "DELETE", query: query, authenticated: authenticated)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.server("Delete failed")
        }
    }

    func uploadMultipart(
        path: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        fieldName: String = "file"
    ) async throws -> Data {
        let boundary = UUID().uuidString
        var request = try await buildRequest(path: path, method: "POST", authenticated: true)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.server("No response") }
        guard (200...299).contains(http.statusCode) else {
            throw parseError(data: data, status: http.statusCode)
        }
        return data
    }

    private func buildRequest(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        authenticated: Bool
    ) async throws -> URLRequest {
        guard var components = URLComponents(string: AppConfig.apiBaseURL + path) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if authenticated, let token = tokenStore.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest, retryOn401: Bool = true) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.server("No response") }

            if http.statusCode == 401, retryOn401, request.value(forHTTPHeaderField: "Authorization") != nil {
                try await refreshTokens()
                var retry = request
                if let token = tokenStore.accessToken {
                    retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                return try await perform(retry, retryOn401: false)
            }

            guard (200...299).contains(http.statusCode) else {
                throw parseError(data: data, status: http.statusCode)
            }

            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    private func refreshTokens() async throws {
        guard let refreshToken = tokenStore.tokens?.refreshToken else {
            throw APIError.unauthorized
        }
        let response: LoginResponse = try await post(
            path: APIPath.mobileRefresh,
            body: RefreshRequest(refreshToken: refreshToken),
            authenticated: false
        )
        tokenStore.save(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresIn: response.expiresIn
        )
    }

    private func parseError(data: Data, status: Int) -> APIError {
        if let body = try? decoder.decode(APIErrorBody.self, from: data), let msg = body.error, !msg.isEmpty {
            if status == 401 { return .server(msg) }
            if status == 403 { return .forbidden(msg) }
            if status == 400 { return .badRequest(msg) }
            return .server(msg)
        }
        if status == 401 { return .unauthorized }
        return .server("Request failed (\(status))")
    }
}
