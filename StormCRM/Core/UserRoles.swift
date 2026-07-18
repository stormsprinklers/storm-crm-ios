import Foundation

enum UserRoles {
    static func isFieldRole(_ role: String) -> Bool {
        role == "TECH" || role == "INSTALLER"
    }

    static func canViewMaintenancePlans(_ role: String) -> Bool {
        role == "CSR" || role == "MANAGER" || role == "ADMIN" || role == "TECH" || role == "INSTALLER" || role == "SALES"
    }

    static func canManageEnrollments(_ role: String) -> Bool {
        role == "CSR" || role == "MANAGER" || role == "ADMIN" || role == "TECH" || role == "SALES"
    }

    static func canEditVisitOfficeFields(_ role: String) -> Bool {
        !isFieldRole(role)
    }

    static func canDeleteVisit(_ role: String) -> Bool {
        role == "ADMIN"
    }

    static func canViewReporting(_ role: String) -> Bool {
        role == "ADMIN" || role == "MANAGER" || role == "CSR" || role == "SALES" || role == "TECH"
    }

    static func canEditCustomers(_ role: String) -> Bool {
        !isFieldRole(role)
    }

    static func canEditCustomerTags(_ role: String) -> Bool {
        role == "ADMIN" || role == "MANAGER" || role == "CSR" || role == "SALES" || role == "TECH" || role == "INSTALLER"
    }

    static func canFlagDoNotService(_ role: String) -> Bool {
        role == "ADMIN" || role == "MANAGER" || role == "CSR" || role == "SALES" || role == "TECH"
    }

    static func canManageCustomerStatus(_ role: String) -> Bool {
        role == "ADMIN" || role == "MANAGER"
    }

    static func canManageChecklists(_ role: String) -> Bool {
        role == "ADMIN" || role == "MANAGER"
    }

    static func canControlRachio(_ role: String) -> Bool {
        // Field may start/stop on accessible properties (server-enforced).
        role == "ADMIN" || role == "MANAGER" || role == "CSR" || role == "TECH" || role == "INSTALLER" || role == "SALES"
    }

    static func canLinkRachio(_ role: String) -> Bool {
        canEditVisitOfficeFields(role)
    }
}
