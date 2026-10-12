import Foundation

struct CompanyBrandingDTO: Decodable {
    let name: String?
    let brandLogoUrl: String?
    let irrigationFeaturesEnabled: Bool?
    let holidayLightingFeaturesEnabled: Bool?
    let maintenancePlansFeaturesEnabled: Bool?
    let emailLogoUrl: String?
    let phone: String?
    let termsOfServiceUrl: String?
    let termsUrl: String?
    let tosUrl: String?
    let privacyPolicyUrl: String?
    let privacyUrl: String?

    /// First non-empty terms URL from known company-settings keys.
    var resolvedTermsOfServiceURL: URL? {
        Self.firstURL(from: [termsOfServiceUrl, termsUrl, tosUrl])
    }

    /// First non-empty privacy URL from known company-settings keys.
    var resolvedPrivacyPolicyURL: URL? {
        Self.firstURL(from: [privacyPolicyUrl, privacyUrl])
    }

    private static func firstURL(from candidates: [String?]) -> URL? {
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
    @Published private(set) var privacyPolicyURL: URL?
    @Published private(set) var isLoaded = false

    @Published private(set) var irrigationEnabled = true
    @Published private(set) var holidayLightingEnabled = false
    @Published private(set) var maintenancePlansEnabled = true
    var aiName: String { "\(companyName.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "Company") AI" }
    var isHolidayCompany: Bool {
        companyName.lowercased().replacingOccurrences(of: "&", with: "and") == "chestnut and cheer" || (holidayLightingEnabled && !irrigationEnabled)
    }

    func reset() {
        companyName = "Storm Sprinklers"
        logoUrl = nil
        termsOfServiceURL = nil
        privacyPolicyURL = nil
        irrigationEnabled = true
        holidayLightingEnabled = false
        maintenancePlansEnabled = true
        isLoaded = false
    }

    func load(api: APIClient) async {
        do {
            let settings: CompanyBrandingDTO = try await api.get(path: APIPath.companySettings)
            if let name = settings.name, !name.isEmpty {
                companyName = name
            }
            logoUrl = settings.brandLogoUrl ?? settings.emailLogoUrl
            let chestnut = companyName.lowercased().replacingOccurrences(of: "&", with: "and") == "chestnut and cheer"
            holidayLightingEnabled = chestnut || settings.holidayLightingFeaturesEnabled == true
            irrigationEnabled = !chestnut && settings.irrigationFeaturesEnabled != false
            maintenancePlansEnabled = !isHolidayCompany && settings.maintenancePlansFeaturesEnabled != false
            termsOfServiceURL = settings.resolvedTermsOfServiceURL
            privacyPolicyURL = settings.resolvedPrivacyPolicyURL
        } catch {
            // Keep Storm defaults when settings are unavailable.
        }
        isLoaded = true
    }
}
