import Foundation

enum ServicePlanFormatting {
    static func currency(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD"))
    }

    static func billingFrequencyLabel(_ value: String) -> String {
        switch value {
        case "MONTHLY": return "Monthly"
        case "QUARTERLY": return "Quarterly"
        case "ANNUAL": return "Annual"
        case "MULTI_YEAR_UPFRONT": return "Multi-year upfront"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func statusLabel(_ status: String) -> String {
        status.replacingOccurrences(of: "_", with: " ")
    }

    static func monthYear(_ month: Int, _ year: Int) -> String {
        var components = DateComponents()
        components.month = month
        components.day = 1
        components.year = year
        if let date = Calendar.current.date(from: components) {
            return date.formatted(.dateTime.month(.abbreviated).year())
        }
        return "Month \(month) \(year)"
    }
}

struct MaintenancePlanTemplatesResponse: Decodable {
    let templates: [MaintenancePlanTemplateDTO]
}

struct MaintenancePlanTemplateDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let basePrice: Double
    let active: Bool
    let allowedBillingFrequencies: [String]
    let autoRenewDefault: Bool
    let benefits: [String]?
    let addons: [MaintenancePlanAddonDTO]?

    enum CodingKeys: String, CodingKey {
        case id, name, description, basePrice, active, allowedBillingFrequencies, autoRenewDefault, benefits, addons
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        basePrice = try container.decodeFlexibleDouble(forKey: .basePrice) ?? 0
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
        allowedBillingFrequencies = try container.decodeIfPresent([String].self, forKey: .allowedBillingFrequencies) ?? ["ANNUAL"]
        autoRenewDefault = try container.decodeIfPresent(Bool.self, forKey: .autoRenewDefault) ?? true
        benefits = try container.decodeIfPresent([String].self, forKey: .benefits)
        addons = try container.decodeIfPresent([MaintenancePlanAddonDTO].self, forKey: .addons)
    }

    var activeAddons: [MaintenancePlanAddonDTO] {
        (addons ?? []).filter(\.active)
    }
}

struct MaintenancePlanAddonDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let price: Double
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, description, price, active
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        price = try container.decodeFlexibleDouble(forKey: .price) ?? 0
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
    }
}

struct MaintenanceEnrollmentsListResponse: Decodable {
    let enrollments: [MaintenanceEnrollmentDTO]
}

struct MaintenanceEnrollmentDTO: Decodable, Identifiable {
    let id: String
    let status: String
    let billingFrequency: String
    let startDate: String
    let endDate: String?
    let nextBillingDate: String?
    let autoRenew: Bool
    let acceptedAt: String?
    let customer: MaintenanceEnrollmentCustomerDTO
    let property: MaintenanceEnrollmentPropertyDTO
    let template: MaintenanceEnrollmentTemplateDTO
    let planVisits: [MaintenancePlanVisitDTO]?
    let billingPeriods: [MaintenanceBillingPeriodDTO]?

    var isActivePlan: Bool {
        ["ACTIVE", "PENDING_RENEWAL", "EXPIRING_SOON"].contains(status)
    }

    var canAccept: Bool {
        status == "DRAFT" || status == "SENT"
    }
}

struct MaintenanceEnrollmentCustomerDTO: Decodable {
    let id: String
    let name: String
    let phone: String?
    let email: String?
    let doNotService: Bool?
}

struct MaintenanceEnrollmentPropertyDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let address: String?
}

struct MaintenanceEnrollmentTemplateDTO: Decodable {
    let id: String
    let name: String
    let basePrice: Double

    enum CodingKeys: String, CodingKey {
        case id, name, basePrice
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        basePrice = try container.decodeFlexibleDouble(forKey: .basePrice) ?? 0
    }
}

struct MaintenancePlanVisitDTO: Decodable, Identifiable {
    let id: String
    let dueYear: Int
    let dueMonth: Int
    let status: String
    let visitTemplate: MaintenancePlanVisitTemplateDTO?
    let visit: MaintenancePlanLinkedVisitDTO?
}

struct MaintenancePlanVisitTemplateDTO: Decodable {
    let visitTitle: String?
    let name: String?
}

struct MaintenancePlanLinkedVisitDTO: Decodable, Identifiable {
    let id: String
    let title: String
    let startAt: String
}

struct MaintenanceBillingPeriodDTO: Decodable, Identifiable {
    let id: String
    let periodStart: String
    let periodEnd: String
    let amount: Double
    let status: String
    let dueDate: String

    enum CodingKeys: String, CodingKey {
        case id, periodStart, periodEnd, amount, status, dueDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        periodStart = try container.decode(String.self, forKey: .periodStart)
        periodEnd = try container.decode(String.self, forKey: .periodEnd)
        amount = try container.decodeFlexibleDouble(forKey: .amount) ?? 0
        status = try container.decode(String.self, forKey: .status)
        dueDate = try container.decode(String.self, forKey: .dueDate)
    }
}

struct CreateMaintenanceEnrollmentBody: Encodable {
    let customerId: String
    let propertyId: String
    let templateId: String
    let billingFrequency: String
    let startDate: String
    let autoRenew: Bool
    let selectedAddonIds: [String]
    let mobileReturn: Bool
    let platform: String

    init(
        customerId: String,
        propertyId: String,
        templateId: String,
        billingFrequency: String,
        startDate: String,
        autoRenew: Bool,
        selectedAddonIds: [String],
        mobileReturn: Bool = true,
        platform: String = "ios"
    ) {
        self.customerId = customerId
        self.propertyId = propertyId
        self.templateId = templateId
        self.billingFrequency = billingFrequency
        self.startDate = startDate
        self.autoRenew = autoRenew
        self.selectedAddonIds = selectedAddonIds
        self.mobileReturn = mobileReturn
        self.platform = platform
    }
}
