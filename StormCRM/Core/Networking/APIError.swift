import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case forbidden(String)
    case badRequest(String)
    case server(String)
    case decoding(Error)
    case network(Error)

    var message: String {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .unauthorized: return "Session expired. Please sign in again."
        case .forbidden(let msg): return msg
        case .badRequest(let msg): return msg
        case .server(let msg): return msg
        case .decoding(let err): return "Invalid response: \(err.localizedDescription)"
        case .network(let err): return err.localizedDescription
        }
    }

    var errorDescription: String? { message }
}

struct APIErrorBody: Decodable {
    let error: String?
}
