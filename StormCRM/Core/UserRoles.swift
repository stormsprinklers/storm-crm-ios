import Foundation

enum UserRoles {
    static func isFieldRole(_ role: String) -> Bool {
        role == "TECH" || role == "INSTALLER"
    }

    static func canViewProfitMargins(_ role: String) -> Bool {
        role == "ADMIN" || role == "MANAGER"
    }

    static func canViewMaintenancePlans(_ role: String) -> Bool {
        !isFieldRole(role)
    }
}
