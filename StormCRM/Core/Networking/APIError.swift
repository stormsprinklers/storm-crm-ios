import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case forbidden(String)
    case badRequest(String)
    case server(String)
    /// Maintenance enrollment (and similar) blocked until a card is saved via Stripe Setup Checkout.
    case cardRequired(message: String, setupUrl: String)
    case decoding(Error)
    case network(Error)

    var message: String {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .unauthorized: return "Session expired. Please sign in again."
        case .forbidden(let msg): return msg
        case .badRequest(let msg): return msg
        case .server(let msg): return msg
        case .cardRequired(let msg, _): return msg
        case .decoding(let err):
            if let decoding = err as? DecodingError {
                return "Invalid response: \(Self.describe(decoding))"
            }
            return "Invalid response: \(err.localizedDescription)"
        case .network(let err): return err.localizedDescription
        }
    }

    var errorDescription: String? { message }

    var setupUrl: URL? {
        if case .cardRequired(_, let raw) = self {
            return URL(string: raw)
        }
        return nil
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing field '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(let type, let context):
            return "Wrong type for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(let type, let context):
            return "Missing value for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return error.localizedDescription
        }
    }
}

struct APIErrorBody: Decodable {
    let error: String?
    let code: String?
    let setupUrl: String?
}
