import Foundation

struct CompanyBrandingDTO: Decodable {
    let name: String?
    let emailLogoUrl: String?
    let phone: String?
}

@MainActor
final class CompanyBranding: ObservableObject {
    @Published private(set) var companyName = "Storm Sprinklers"
    @Published private(set) var logoUrl: String?
    @Published private(set) var isLoaded = false

    func load(api: APIClient) async {
        do {
            let settings: CompanyBrandingDTO = try await api.get(path: APIPath.companySettings)
            if let name = settings.name, !name.isEmpty {
                companyName = name
            }
            logoUrl = settings.emailLogoUrl
        } catch {
            // Keep Storm defaults when settings are unavailable.
        }
        isLoaded = true
    }
}
