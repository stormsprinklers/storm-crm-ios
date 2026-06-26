import Foundation

enum AppConfig {
    /// Override in Xcode scheme: API_BASE_URL
    static var apiBaseURL: String {
        if let env = ProcessInfo.processInfo.environment["API_BASE_URL"], !env.isEmpty {
            return env.hasSuffix("/") ? String(env.dropLast()) : env
        }
        #if DEBUG
        return "http://localhost:3000"
        #else
        return "https://crm.stormsprinklers.com"
        #endif
    }
}
