import Foundation
import SwiftUI
import UIKit

@MainActor
final class HolidayQuoteViewModel: ObservableObject {
    @Published var quoteID: String?
    @Published var customerID: String?
    @Published var propertyID: String?
    @Published var customerName = ""
    @Published var address = ""
    @Published var city = ""
    @Published var state = ""
    @Published var zip = ""
    @Published var center: HLPoint?
    @Published var options: [HLDesign] = [HLDesign()]
    @Published var activeID = ""
    @Published var catalog: HLCatalog?
    @Published var pricing: HLPricing?
    @Published var sourcePhotoURL: String?
    @Published var photo: UIImage?
    @Published var photoUnsaved = false
    @Published var linkedVisit = false
    @Published var estimateID: String?
    @Published var busy = false
    @Published var generating = false
    @Published var dirty = false
    @Published var error: String?
    @Published var notice: String?
    private var updatedAt: String?
    private var rootSelections = HLSelections()
    private var loaded = false
    let visitID: String?
    let initialCustomerID: String?
    let initialPropertyID: String?

    init(quoteID: String? = nil, visitID: String? = nil, customerID: String? = nil, propertyID: String? = nil) {
        self.quoteID = quoteID; self.visitID = visitID; self.initialCustomerID = customerID; self.initialPropertyID = propertyID
        self.customerID = customerID; self.propertyID = propertyID; self.linkedVisit = visitID != nil
        activeID = options[0].id
    }
    var activeIndex: Int { options.firstIndex { $0.id == activeID } ?? 0 }
    var active: HLDesign { options[activeIndex] }
    var title: String { customerName.isEmpty ? (address.isEmpty ? "Holiday quote" : address) : customerName }
    var path: String { "/api/holiday-lighting/quotes/\(quoteID ?? "")" }
    var hasMeasurements: Bool { options.allSatisfy { $0.measurements.segments.contains { $0.length > 0 } || !$0.measurements.placements.isEmpty || !$0.selections.services.isEmpty } }

    func edit(invalidatePreview: Bool = true, _ update: (inout HLDesign) -> Void) {
        var next = active
        update(&next)
        if invalidatePreview { next.previewURL = nil }
        options[activeIndex] = next
        dirty = true; notice = nil
    }
    func optionBinding<T>(_ keyPath: WritableKeyPath<HLDesign, T>, invalidatePreview: Bool = false) -> Binding<T> {
        Binding(get: { self.active[keyPath: keyPath] }, set: { value in self.edit(invalidatePreview: invalidatePreview) { $0[keyPath: keyPath] = value } })
    }
    func selectionBinding<T>(_ keyPath: WritableKeyPath<HLSelections, T>, invalidatePreview: Bool = true) -> Binding<T> {
        Binding(get: { self.active.selections[keyPath: keyPath] }, set: { value in self.edit(invalidatePreview: invalidatePreview) { $0.selections[keyPath: keyPath] = value } })
    }
    func selectOption(_ id: String) { activeID = id; pricing = nil; dirty = true }
    func addOption(copy: Bool) {
        guard options.count < 5 else { return }
        var option = copy ? active : HLDesign(selections: active.selections)
        option.id = UUID().uuidString; option.label = "Option \(options.count + 1)"
        if !copy { option.previewURL = nil }
        options.append(option); activeID = option.id; dirty = true; pricing = nil
    }
    func deleteOption() {
        guard options.count > 1 else { return }
        options.remove(at: activeIndex); activeID = options[0].id; dirty = true; pricing = nil
    }
    func removeSegment(_ id: String) {
        edit { option in
            option.measurements.segments.removeAll { $0.id == id }
            var strands = option.measurements.strands
            for index in strands.indices { strands[index].segmentIDs.removeAll { $0 == id } }
            option.measurements.strands = strands.filter { !$0.segmentIDs.isEmpty }
        }
    }
    func load(api: APIClient) async {
        guard !loaded else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            if let quoteID {
                let response: HLQuoteResponse = try await api.get(path: "/api/holiday-lighting/quotes/\(quoteID)")
                apply(response); loaded = true
            } else {
                let response: HLCatalogResponse = try await api.get(path: "/api/settings/holiday-lighting")
                catalog = response.catalog
                if let style = catalog?.quoteDefaults?.defaultLightStyleKey { options[0].selections.style = style }
                if let visitID {
                    let visit: VisitDetailDTO = try await api.get(path: APIPath.visit(visitID))
                    customerID = visit.customer?.id; propertyID = visit.property?.id; customerName = visit.customer?.name ?? ""
                    address = visit.address ?? ""; city = visit.city ?? ""; state = visit.state ?? ""; zip = visit.zip ?? ""
                } else if let customerID {
                    let customer: CustomerDTO = try await api.get(path: APIPath.customer(customerID))
                    customerName = customer.name; address = customer.address ?? ""; city = customer.city ?? ""; state = customer.state ?? ""; zip = customer.zip ?? ""
                    if let propertyID {
                        let properties: [CustomerPropertyDTO] = try await api.get(path: APIPath.customerProperties(customerID))
                        if let property = properties.first(where: { $0.id == propertyID }) { applyProperty(property) }
                    }
                }
                loaded = true; dirty = true
            }
            if let sourcePhotoURL { await loadPhoto(sourcePhotoURL, api: api) }
        } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
    }
    func reload(api: APIClient) async {
        loaded = false; photo = nil; photoUnsaved = false
        await load(api: api)
    }
    func segmentBinding(_ id: String) -> Binding<HLSegment> {
        Binding(get: { self.active.measurements.segments.first { $0.id == id } ?? HLSegment(fields: [:]) }, set: { value in
            self.edit { option in var rows = option.measurements.segments; if let index = rows.firstIndex(where: { $0.id == id }) { rows[index] = value; option.measurements.segments = rows } }
        })
    }
    func placementBinding(_ id: String) -> Binding<HLPlacement> {
        Binding(get: { self.active.measurements.placements.first { $0.id == id } ?? HLPlacement(fields: [:]) }, set: { value in
            self.edit { option in var rows = option.measurements.placements; if let index = rows.firstIndex(where: { $0.id == id }) { rows[index] = value; option.measurements.placements = rows } }
        })
    }
    func serviceBinding(_ id: String) -> Binding<HLService> {
        Binding(get: { self.active.selections.services.first { $0.id == id } ?? HLService(fields: [:]) }, set: { value in
            self.edit(invalidatePreview: false) { option in var rows = option.selections.services; if let index = rows.firstIndex(where: { $0.id == id }) { rows[index] = value; option.selections.services = rows } }
        })
    }
    func apply(_ response: HLQuoteResponse) {
        let quote = response.quote
        quoteID = quote.id; customerID = quote.customerId; propertyID = quote.propertyId; linkedVisit = quote.visitId != nil
        customerName = quote.customer?.name ?? customerName
        address = quote.address ?? ""; city = quote.city ?? ""; state = quote.state ?? ""; zip = quote.zip ?? ""
        if let lat = quote.lat, let lng = quote.lng { center = HLPoint(lat: lat, lng: lng) }
        rootSelections = quote.selections
        var designs: [HLDesign] = quote.selections.value("designOptions", fallback: [])
        if designs.isEmpty {
            var fallback = HLDesign(measurements: quote.measurements, selections: quote.selections)
            fallback.previewURL = quote.previewImageUrl; designs = [fallback]
        }
        options = designs
        let selected: String = quote.selections.value("activeDesignOptionId", fallback: designs[0].id)
        activeID = designs.contains(where: { $0.id == selected }) ? selected : designs[0].id
        if options[activeIndex].previewURL == nil, let preview = quote.previewImageUrl { options[activeIndex].previewURL = preview }
        catalog = response.catalog ?? catalog; pricing = response.pricing
        updatedAt = quote.updatedAt; sourcePhotoURL = quote.sourcePhotoUrl; estimateID = quote.estimate?.id
        dirty = false
    }
    func applyProperty(_ property: CustomerPropertyDTO) {
        propertyID = property.id; address = property.address ?? ""; city = property.city ?? ""; state = property.state ?? ""; zip = property.zip ?? ""
        center = nil; dirty = true
    }
    func chooseCustomer(_ customer: CustomerDTO) {
        customerID = customer.id; propertyID = nil; customerName = customer.name
        address = customer.address ?? ""; city = customer.city ?? ""; state = customer.state ?? ""; zip = customer.zip ?? ""
        center = nil; dirty = true
    }
    func payload() -> [String: JSONValue] {
        var selections = active.selections
        // Preserve root settings as well as option-specific settings from the CRM.
        var fields = rootSelections.fields
        fields.merge(selections.fields) { _, next in next }
        selections.fields = fields
        selections.put("designOptions", options); selections.put("activeDesignOptionId", activeID)
        var body: [String: JSONValue] = [
            "customerId": customerID.map(JSONValue.string) ?? .null,
            "propertyId": propertyID.map(JSONValue.string) ?? .null,
            "address": .string(address), "city": .string(city), "state": .string(state), "zip": .string(zip),
            "lat": center.map { .number($0.lat) } ?? .null, "lng": center.map { .number($0.lng) } ?? .null,
            "previewImageUrl": active.previewURL.map(JSONValue.string) ?? .null
        ]
        if let visitID { body["visitId"] = .string(visitID) }
        if let updatedAt { body["expectedUpdatedAt"] = .string(updatedAt) }
        var holder = HLMeasurements(); holder.put("measurements", active.measurements); holder.put("selections", selections)
        body.merge(holder.fields) { _, next in next }
        return body
    }
    @discardableResult
    func save(api: APIClient) async -> Bool {
        guard !busy && !generating else { return false }
        busy = true; error = nil; notice = nil
        defer { busy = false }
        do {
            let response: HLQuoteResponse
            if quoteID == nil {
                response = try await api.post(path: "/api/holiday-lighting/quotes", body: payload())
                quoteID = response.quote.id
                let detail: HLQuoteResponse = try await api.get(path: path)
                apply(detail)
            } else {
                response = try await api.patch(path: path, body: payload())
                apply(response)
            }
            notice = "Saved to CRM"; return true
        } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription; return false }
    }
    func locate(api: APIClient) async {
        guard !busy, !generating else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let point: HLPoint = try await api.post(path: "/api/holiday-lighting/geocode", body: ["address": address, "city": city, "state": state, "zip": zip])
            center = point; dirty = true
        } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
    }
    func createEstimate(api: APIClient, revise: Bool) async -> String? {
        guard customerID != nil else { error = "Select a customer before creating an estimate."; return nil }
        guard hasMeasurements else { error = "Each option needs measurements, trees/bushes, or an additional service."; return nil }
        guard await save(api: api) else { return nil }
        busy = true; defer { busy = false }
        struct Response: Decodable { struct Estimate: Decodable { let id: String }; let estimate: Estimate }
        do {
            let response: Response = try await api.post(path: path + "/create-estimate", body: ["mode": revise ? "revise" : "new"])
            estimateID = response.estimate.id
            let refreshed: HLQuoteResponse? = try? await api.get(path: path)
            if let refreshed { apply(refreshed) }
            return response.estimate.id
        } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription; return nil }
    }
    func loadPhoto(_ stored: String, api: APIClient) async {
        guard let url = BlobImageURL.resolved(stored) else { return }
        do {
            if url.host == URL(string: AppConfig.apiBaseURL)?.host {
                let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let data = try await api.getData(path: url.path, query: parts?.queryItems ?? [])
                photo = UIImage(data: data)
            } else {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.server("Could not load property photo") }
                photo = UIImage(data: data)
            }
        } catch { self.error = "Could not load the saved property photo. Choose or take another photo." }
    }
    func uploadPhoto(_ image: UIImage, api: APIClient) async {
        guard await save(api: api) else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let clean = try HLPhotoRenderer.jpeg(image)
            let response: HLQuoteResponse = try await api.uploadImages(path: path + "/photo", fields: ["expectedUpdatedAt": updatedAt ?? ""], images: [("file", clean)], timeout: 60)
            apply(response); photo = UIImage(data: clean); photoUnsaved = false
            let detail: HLQuoteResponse? = try? await api.get(path: path)
            if let detail { apply(detail) }
            notice = "Property photo saved"
        } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
    }
    func streetView(api: APIClient, heading: Double, pitch: Double) async {
        guard await save(api: api) else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let data = try await api.getData(path: path + "/photo", query: [URLQueryItem(name: "heading", value: String(heading)), URLQueryItem(name: "pitch", value: String(pitch))])
            guard let image = UIImage(data: data) else { throw APIError.server("No Street View photo found. Take or select a property photo instead.") }
            photo = image; photoUnsaved = true
            notice = "Street View loaded — tap Save photo to attach it"
        } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
    }
    func generatePreview(api: APIClient) async {
        guard let photo else { error = "Choose a property photo first."; return }
        guard !active.markup.isEmpty else { error = "Paint the areas that should receive lights first."; return }
        guard sourcePhotoURL != nil, !photoUnsaved else { error = "Save the property photo before generating a preview."; return }
        guard await save(api: api) else { return }
        generating = true; error = nil; defer { generating = false }
        do {
            let clean = try HLPhotoRenderer.jpeg(photo)
            let marked = try HLPhotoRenderer.jpeg(photo, strokes: active.markup)
            guard clean.count + marked.count < 4 * 1024 * 1024 else { throw APIError.badRequest("Photo is too large. Select a smaller image.") }
            struct Preview: Decodable { let previewImageUrl: String }
            let _: Preview = try await api.uploadImages(path: path + "/visualize", fields: ["optionId": activeID, "persistOptionPreview": "true"], images: [("clean", clean), ("marked", marked)], timeout: 290)
            let response: HLQuoteResponse = try await api.get(path: path)
            apply(response); notice = "Preview saved to CRM"
        } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
    }
}
