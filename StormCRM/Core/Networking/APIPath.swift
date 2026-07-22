import Foundation

enum APIPath {
    static let mobileLogin = "/api/mobile/auth/login"
    static let mobileMfa = "/api/mobile/auth/mfa"
    static let mobileMfaResend = "/api/mobile/auth/mfa/resend"
    static let mobileRefresh = "/api/mobile/auth/refresh"
    static let mobileLogout = "/api/mobile/auth/logout"
    static let mobileSchedule = "/api/mobile/schedule"
    static let mobileActiveVisit = "/api/mobile/visits/active"
    static let mobileInboxSms = "/api/mobile/inbox/sms/conversations"
    static let mobileTimeSegments = "/api/mobile/time-segments"
    static let mobileMissedTransfers = "/api/mobile/voice/missed-transfers"
    static let mobileDashboard = "/api/mobile/dashboard"

    static func visit(_ id: String) -> String { "/api/visits/\(id)" }
    static func visitTime(_ id: String) -> String { "/api/visits/\(id)/time" }
    static func visitNotes(_ id: String) -> String { "/api/visits/\(id)/notes" }
    static func visitAttachments(_ id: String) -> String { "/api/visits/\(id)/attachments" }
    static func visitChecklists(_ id: String) -> String { "/api/visits/\(id)/checklists" }
    static let checklistTemplates = "/api/checklist-templates"
    static let settingsChecklists = "/api/settings/checklists"
    static func visitLineItems(_ id: String) -> String { "/api/visits/\(id)/line-items" }
    static func visitPartsRun(_ id: String) -> String { "/api/visits/\(id)/parts-run" }
    static func visitMaintenancePlan(_ id: String) -> String { "/api/visits/\(id)/maintenance-plan" }
    static func visitInvoice(_ id: String) -> String { "/api/visits/\(id)/invoice" }
    static func invoice(_ id: String) -> String { "/api/invoices/\(id)" }
    static func invoiceSend(_ id: String) -> String { "/api/invoices/\(id)/send" }
    static let maintenancePlanTemplates = "/api/maintenance-plans/templates"
    static let maintenancePlanEnrollments = "/api/maintenance-plans/enrollments"
    static func maintenancePlanEnrollment(_ id: String) -> String {
        "/api/maintenance-plans/enrollments/\(id)"
    }
    static func maintenancePlanEnrollmentAccept(_ id: String) -> String {
        "/api/maintenance-plans/enrollments/\(id)/accept"
    }
    static func visitDiscounts(_ id: String) -> String { "/api/visits/\(id)/discounts" }
    static let scheduleFilters = "/api/schedule/filters"
    static let scheduleJobs = "/api/schedule/jobs"
    static let scheduleTimeOff = "/api/schedule/time-off"
    static let priceBookItems = "/api/price-book/items"
    static let priceBookFrequentItems = "/api/price-book/items/frequent"
    static let priceBookDiscounts = "/api/price-book/discounts"
    static func priceBookCategory(_ id: String) -> String { "/api/price-book/categories/\(id)" }
    static let priceBookCategories = "/api/price-book/categories"
    static let estimates = "/api/estimates"
    static func estimate(_ id: String) -> String { "/api/estimates/\(id)" }
    static func estimateSend(_ id: String) -> String { "/api/estimates/\(id)/send" }
    static func estimateSignature(_ id: String) -> String { "/api/estimates/\(id)/signature" }
    static func estimateLineItems(_ id: String) -> String { "/api/estimates/\(id)/line-items" }
    static func estimateDiscounts(_ id: String) -> String { "/api/estimates/\(id)/discounts" }
    static func estimateOptions(_ id: String) -> String { "/api/estimates/\(id)/options" }
    static func estimateCopy(_ id: String) -> String { "/api/estimates/\(id)/copy" }
    static func estimatePostApproval(_ id: String) -> String { "/api/estimates/\(id)/post-approval" }
    static let estimateSettings = "/api/settings/estimates"
    static func visitChecklistItem(_ visitId: String, checklistId: String, itemId: String) -> String {
        "/api/visits/\(visitId)/checklists/\(checklistId)/items/\(itemId)"
    }
    static func visitChecklistComplete(_ visitId: String, checklistId: String) -> String {
        "/api/visits/\(visitId)/checklists/\(checklistId)/complete"
    }

    static let visits = "/api/visits"
    static let customers = "/api/customers"
    static func customer(_ id: String) -> String { "/api/customers/\(id)" }
    static func customerProperties(_ id: String) -> String { "/api/customers/\(id)/properties" }
    static func customerHistory(_ id: String) -> String { "/api/customers/\(id)/history" }
    static func customerNotes(_ id: String) -> String { "/api/customers/\(id)/notes" }
    static func customerAttachments(_ id: String) -> String { "/api/customers/\(id)/attachments" }
    static let mapsEmbed = "/api/maps/embed"
    static func irrigationMap(customerId: String, propertyId: String) -> String {
        "/api/customers/\(customerId)/properties/\(propertyId)/irrigation-map"
    }
    static func irrigationProgram(customerId: String, propertyId: String) -> String {
        "/api/customers/\(customerId)/properties/\(propertyId)/irrigation-program"
    }
    static func irrigationMapAerial(customerId: String, propertyId: String) -> String {
        "/api/customers/\(customerId)/properties/\(propertyId)/irrigation-map/aerial"
    }
    static func rachio(customerId: String, propertyId: String) -> String {
        "/api/customers/\(customerId)/properties/\(propertyId)/rachio"
    }
    static func rachioStartZone(customerId: String, propertyId: String, zoneId: String) -> String {
        "/api/customers/\(customerId)/properties/\(propertyId)/rachio/zones/\(zoneId)/start"
    }
    static func rachioStop(customerId: String, propertyId: String) -> String {
        "/api/customers/\(customerId)/properties/\(propertyId)/rachio/stop"
    }
    static func rachioLink(customerId: String, propertyId: String) -> String {
        "/api/customers/\(customerId)/properties/\(propertyId)/rachio/link"
    }
    static let settingsRachioDevices = "/api/settings/rachio/devices"

    static let timeClock = "/api/time-clock"
    static let timesheets = "/api/timesheets"
    static let smsConversations = "/api/inbox/sms/conversations"
    static let smsConversationResolve = "/api/inbox/sms/conversations/resolve"
    static func smsMessages(_ conversationId: String) -> String {
        "/api/inbox/sms/conversations/\(conversationId)/messages"
    }
    static let inboxMediaUpload = "/api/inbox/media/upload"
    static let mobilePushRegister = "/api/mobile/push/register"
    static let mobilePushUnregister = "/api/mobile/push/unregister"
    static let voiceToken = "/api/inbox/voice/token"
    static func voiceTokenPath(platform: String) -> String {
        "/api/inbox/voice/token?platform=\(platform)"
    }
    static let voiceCall = "/api/inbox/voice/call"
    static let voicePresence = "/api/voice/presence"
    static let companySettings = "/api/settings/company"
    static func reporting(_ type: String) -> String { "/api/reporting/\(type)" }
    static let paymentsCheckout = "/api/payments/checkout"
    static let paymentsConfirm = "/api/payments/confirm"
    static let paymentsManual = "/api/payments/manual"
    static let inboxContacts = "/api/inbox/contacts"
}
