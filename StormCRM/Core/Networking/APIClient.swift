import Foundation

final class APIClient {
    private let tokenStore: TokenStore
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let refreshGate = RefreshGate()

    /// Called on the main actor when the refresh token is rejected and the local session was cleared.
    var onSessionInvalidated: (@MainActor () -> Void)?

    init(tokenStore: TokenStore, session: URLSession = .shared) {
        self.tokenStore = tokenStore
        self.session = session
        self.decoder = JSONCoding.makeDecoder()
        self.encoder = JSONCoding.makeEncoder()
    }

    /// Refresh access/refresh tokens, coalescing concurrent callers onto one network request.
    /// Critical now that every tab stays mounted and may 401 at once.
    @discardableResult
    func refreshSessionTokens() async throws -> LoginResponse {
        try await refreshGate.run { [weak self] in
            guard let self else { throw APIError.unauthorized }
            return try await self.performTokenRefresh()
        }
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
        authenticated: Bool = true,
        headers: [String: String] = [:]
    ) async throws -> T {
        var request = try await buildRequest(
            path: path,
            method: "POST",
            authenticated: authenticated,
            headers: headers
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func post<T: Decodable>(
        path: String,
        authenticated: Bool = true,
        headers: [String: String] = [:]
    ) async throws -> T {
        let request = try await buildRequest(
            path: path,
            method: "POST",
            authenticated: authenticated,
            headers: headers
        )
        return try await perform(request)
    }

    func patch<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        authenticated: Bool = true,
        headers: [String: String] = [:]
    ) async throws -> T {
        var request = try await buildRequest(
            path: path,
            method: "PATCH",
            authenticated: authenticated,
            headers: headers
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func put<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        authenticated: Bool = true,
        headers: [String: String] = [:]
    ) async throws -> T {
        var request = try await buildRequest(
            path: path,
            method: "PUT",
            authenticated: authenticated,
            headers: headers
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func put<T: Decodable>(
        path: String,
        authenticated: Bool = true,
        headers: [String: String] = [:]
    ) async throws -> T {
        let request = try await buildRequest(
            path: path,
            method: "PUT",
            authenticated: authenticated,
            headers: headers
        )
        return try await perform(request)
    }

    func delete(path: String, query: [URLQueryItem] = [], authenticated: Bool = true) async throws {
        let request = try await buildRequest(path: path, method: "DELETE", query: query, authenticated: authenticated)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.server("Delete failed")
        }
    }

    func deleteReturningVisit(
        path: String,
        query: [URLQueryItem] = [],
        authenticated: Bool = true
    ) async throws -> VisitDetailDTO {
        let request = try await buildRequest(path: path, method: "DELETE", query: query, authenticated: authenticated)
        return try await perform(request)
    }

    func uploadMultipart<T: Decodable>(
        path: String,
        query: [URLQueryItem] = [],
        fileData: Data,
        fileName: String,
        mimeType: String,
        fieldName: String = "file"
    ) async throws -> T {
        let data = try await uploadMultipartRaw(
            path: path,
            query: query,
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            fieldName: fieldName
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch let decodingError as DecodingError {
            throw APIError.decoding(decodingError)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func uploadMultipart(
        path: String,
        query: [URLQueryItem] = [],
        fileData: Data,
        fileName: String,
        mimeType: String,
        fieldName: String = "file"
    ) async throws -> Data {
        try await uploadMultipartRaw(
            path: path,
            query: query,
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            fieldName: fieldName
        )
    }

    private func uploadMultipartRaw(
        path: String,
        query: [URLQueryItem] = [],
        fileData: Data,
        fileName: String,
        mimeType: String,
        fieldName: String = "file"
    ) async throws -> Data {
        let boundary = UUID().uuidString
        var request = try await buildRequest(path: path, method: "POST", query: query, authenticated: true)
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
        authenticated: Bool,
        headers: [String: String] = [:]
    ) async throws -> URLRequest {
        guard var components = URLComponents(string: AppConfig.apiBaseURL + path) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

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
                _ = try await refreshSessionTokens()
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
            } catch let decodingError as DecodingError {
                throw APIError.decoding(decodingError)
            } catch {
                throw APIError.decoding(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    private func performTokenRefresh() async throws -> LoginResponse {
        guard let refreshToken = tokenStore.tokens?.refreshToken else {
            throw APIError.unauthorized
        }
        do {
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
            return response
        } catch {
            if Self.shouldInvalidateSession(after: error) {
                tokenStore.clear()
                let callback = onSessionInvalidated
                await MainActor.run {
                    callback?()
                }
            }
            throw error
        }
    }

    private static func shouldInvalidateSession(after error: Error) -> Bool {
        guard let apiError = error as? APIError else { return false }
        switch apiError {
        case .unauthorized:
            return true
        case .server(let msg), .badRequest(let msg), .forbidden(let msg):
            let lower = msg.lowercased()
            return lower.contains("refresh token")
                || lower.contains("invalid refresh")
                || lower.contains("token revoked")
                || lower.contains("refresh_token")
        default:
            return false
        }
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

/// Ensures only one refresh request runs; concurrent 401 retries await the same result.
private final class RefreshGate: @unchecked Sendable {
    private final class InFlight {
        let task: Task<LoginResponse, Error>
        init(_ task: Task<LoginResponse, Error>) { self.task = task }
    }

    private let lock = NSLock()
    private var inFlight: InFlight?

    func run(_ operation: @escaping @Sendable () async throws -> LoginResponse) async throws -> LoginResponse {
        let box: InFlight
        lock.lock()
        if let existing = inFlight {
            lock.unlock()
            return try await existing.task.value
        }
        let created = InFlight(Task {
            try await operation()
        })
        inFlight = created
        box = created
        lock.unlock()

        do {
            let value = try await box.task.value
            clearIfCurrent(box)
            return value
        } catch {
            clearIfCurrent(box)
            throw error
        }
    }

    private func clearIfCurrent(_ box: InFlight) {
        lock.lock()
        if inFlight === box { inFlight = nil }
        lock.unlock()
    }
}
