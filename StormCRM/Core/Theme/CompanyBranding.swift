import Foundation

struct CompanyBrandingDTO: Decodable {
    let name: String?
    let emailLogoUrl: String?
    let phone: String?
    let termsOfServiceUrl: String?
    let termsUrl: String?
    let tosUrl: String?

    /// First non-empty terms URL from known company-settings keys.
    var resolvedTermsOfServiceURL: URL? {
        let candidates = [termsOfServiceUrl, termsUrl, tosUrl]
        for candidate in candidates {
            guard let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                continue
            }
            if let url = URL(string: raw), url.scheme != nil {
                return url
            }
            if let url = URL(string: "https://\(raw)") {
                return url
            }
        }
        return nil
    }
}

@MainActor
final class CompanyBranding: ObservableObject {
    @Published private(set) var companyName = "Storm Sprinklers"
    @Published private(set) var logoUrl: String?
    @Published private(set) var termsOfServiceURL: URL?
    @Published private(set) var isLoaded = false

    func load(api: APIClient) async {
        do {
            let settings: CompanyBrandingDTO = try await api.get(path: APIPath.companySettings)
            if let name = settings.name, !name.isEmpty {
                companyName = name
            }
            logoUrl = settings.emailLogoUrl
            termsOfServiceURL = settings.resolvedTermsOfServiceURL
        } catch {
            // Keep Storm defaults when settings are unavailable.
        }
        isLoaded = true
    }
}
