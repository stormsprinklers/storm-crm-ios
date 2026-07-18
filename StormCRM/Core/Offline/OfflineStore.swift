import Foundation
import SwiftData

enum OfflineStore {
    static let schema = Schema([
        CachedVisit.self,
        CachedCustomer.self,
        CachedProperty.self,
        OutboxMutation.self,
    ])

    static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(
            "StormCRMOffline",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func sharedContext(from container: ModelContainer) -> ModelContext {
        ModelContext(container)
    }
}

enum OfflineCacheBootstrap {
    static func upsertVisits(_ visits: [VisitDTO], context: ModelContext) {
        for visit in visits {
            guard let start = APIDateFormatting.parse(visit.startAt) else { continue }
            guard let data = VisitOfflineCodec.encode(visit) else { continue }

            if let existing = fetchVisit(id: visit.id, context: context) {
                existing.jsonData = data
                existing.startAt = start
                existing.syncedAt = Date()
            } else {
                context.insert(CachedVisit(id: visit.id, jsonData: data, startAt: start))
            }

            if let customer = visit.customer, let customerData = try? JSONCoding.makeEncoder().encode(customer) {
                if let cached = fetchCustomer(id: customer.id, context: context) {
                    cached.jsonData = customerData
                    cached.name = customer.name
                    cached.syncedAt = Date()
                } else {
                    context.insert(CachedCustomer(id: customer.id, jsonData: customerData, name: customer.name))
                }
            }

            if let property = visit.property, let propertyData = PropertyOfflineCodec.encode(property) {
                if let cached = fetchProperty(id: property.id, context: context) {
                    cached.jsonData = propertyData
                    cached.customerId = visit.customer?.id ?? cached.customerId
                    cached.syncedAt = Date()
                } else {
                    context.insert(
                        CachedProperty(
                            id: property.id,
                            customerId: visit.customer?.id ?? "",
                            jsonData: propertyData
                        )
                    )
                }
            }
        }
        try? context.save()
        pruneOldVisits(context: context)
    }

    static func cachedVisit(id: String, context: ModelContext) -> VisitDTO? {
        guard let cached = fetchVisit(id: id, context: context) else { return nil }
        return try? JSONCoding.makeDecoder().decode(VisitDTO.self, from: cached.jsonData)
    }

    private static func pruneOldVisits(context: ModelContext) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -21, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<CachedVisit>(predicate: #Predicate { $0.startAt < cutoff })
        if let stale = try? context.fetch(descriptor) {
            stale.forEach { context.delete($0) }
            try? context.save()
        }
    }

    private static func fetchVisit(id: String, context: ModelContext) -> CachedVisit? {
        var descriptor = FetchDescriptor<CachedVisit>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func fetchCustomer(id: String, context: ModelContext) -> CachedCustomer? {
        var descriptor = FetchDescriptor<CachedCustomer>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func fetchProperty(id: String, context: ModelContext) -> CachedProperty? {
        var descriptor = FetchDescriptor<CachedProperty>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

enum VisitOfflineCodec {
    static func encode(_ visit: VisitDTO) -> Data? {
        var dict: [String: Any] = [
            "id": visit.id,
            "title": visit.title,
            "startAt": visit.startAt,
            "endAt": visit.endAt,
            "division": visit.division,
            "status": visit.status,
        ]
        if let tags = visit.tags { dict["tags"] = tags }
        if let isCallback = visit.isCallback { dict["isCallback"] = isCallback }
        if let address = visit.address { dict["address"] = address }
        if let city = visit.city { dict["city"] = city }
        if let state = visit.state { dict["state"] = state }
        if let zip = visit.zip { dict["zip"] = zip }
        if let customer = visit.customer, let data = try? JSONCoding.makeEncoder().encode(customer),
           let object = try? JSONSerialization.jsonObject(with: data) {
            dict["customer"] = object
        }
        if let property = visit.property, let data = PropertyOfflineCodec.encode(property),
           let object = try? JSONSerialization.jsonObject(with: data) {
            dict["property"] = object
        }
        if let serviceArea = visit.serviceArea, let data = try? JSONCoding.makeEncoder().encode(serviceArea),
           let object = try? JSONSerialization.jsonObject(with: data) {
            dict["serviceArea"] = object
        }
        if let assignedUser = visit.assignedUser, let data = try? JSONCoding.makeEncoder().encode(assignedUser),
           let object = try? JSONSerialization.jsonObject(with: data) {
            dict["assignedUser"] = object
        }
        if let crew = visit.crew, let data = try? JSONCoding.makeEncoder().encode(crew),
           let object = try? JSONSerialization.jsonObject(with: data) {
            dict["crew"] = object
        }
        if let subtotal = visit.subtotal { dict["subtotal"] = subtotal }
        if let total = visit.total { dict["total"] = total }
        if let enRouteEtaSeconds = visit.enRouteEtaSeconds { dict["enRouteEtaSeconds"] = enRouteEtaSeconds }
        if let enRouteEtaAt = visit.enRouteEtaAt { dict["enRouteEtaAt"] = enRouteEtaAt }
        return try? JSONSerialization.data(withJSONObject: dict)
    }
}

enum PropertyOfflineCodec {
    static func encode(_ property: PropertySummary) -> Data? {
        var dict: [String: Any] = ["id": property.id]
        if let name = property.name { dict["name"] = name }
        if let address = property.address { dict["address"] = address }
        if let city = property.city { dict["city"] = city }
        if let state = property.state { dict["state"] = state }
        if let zip = property.zip { dict["zip"] = zip }
        if let latitude = property.latitude { dict["latitude"] = latitude }
        if let longitude = property.longitude { dict["longitude"] = longitude }
        if let aerialImageUrl = property.aerialImageUrl { dict["aerialImageUrl"] = aerialImageUrl }
        if let propertyDiagramUrl = property.propertyDiagramUrl { dict["propertyDiagramUrl"] = propertyDiagramUrl }
        if let irrigationMapStatus = property.irrigationMapStatus { dict["irrigationMapStatus"] = irrigationMapStatus }
        return try? JSONSerialization.data(withJSONObject: dict)
    }
}
