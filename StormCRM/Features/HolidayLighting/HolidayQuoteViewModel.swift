import Foundation
import SwiftUI
import UIKit
import CoreLocation

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
    @Published var previewProgress: Double?
    @Published var previewStage = ""
    @Published var previewComplete = false
    @Published private var savedDraft: Data?
    private var pricingByOption: [String: HLPricing] = [:]
    var dirty: Bool {
        get { savedDraft == nil || draftData() != savedDraft }
        set { if !newValue { savedDraft = draftData() } }
    }
    private func draftData() -> Data? {
        HLQuoteDraftSnapshot(customerID: customerID, propertyID: propertyID, address: [address, city, state, zip], center: center, options: options).encoded()
    }
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
    var hasMeasurements: Bool { options.allSatisfy { $0.measurements.segments.contains { $0.length > 0 } || !$0.measurements.placements.isEmpty || !$0.selections.services.isEmpty || ($0.selections.adjustments[$0.selections.pricingMode]?.lineItems?.contains { $0.kind != "included" } ?? false) } }

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
    func selectOption(_ id: String) { guard id != activeID, options.contains(where: { $0.id == id }) else { return }; activeID = id; pricing = pricingByOption[id] }
    func addOption(copy: Bool) {
        guard options.count < 5 else { return }
        var option = copy ? active : HLDesign(selections: active.selections)
        option.id = UUID().uuidString; option.label = "Option \(options.count + 1)"
        if !copy { option.previewURL = nil; option.previewPrompt = ""; option.selections.completedSteps = []; option.selections.adjustments = [:]; option.selections.services = []; option.selections.notes = "" }
        options.append(option); activeID = option.id; dirty = true; pricing = nil
    }
    func deleteOption() {
        guard options.count > 1 else { return }
        options.remove(at: activeIndex); activeID = options[0].id; dirty = true; pricing = pricingByOption[activeID]
    }
    var quoteLines: [HLQuoteLine] {
        if let lines = active.selections.adjustments[active.selections.pricingMode]?.lineItems { return lines }
        var lines = (pricing?.optionDetails[active.selections.pricingMode]?.displayLines ?? []).enumerated().map { index, line in
            HLQuoteLine(id: "\(activeID)-\(active.selections.pricingMode)-\(index)", name: line.name, description: line.description, unitPrice: line.total, kind: line.name.lowercased().contains("parts") ? "parts" : "labor")
        }
        lines += active.selections.services.map { HLQuoteLine(id: $0.id, name: $0.name, description: $0.detail, quantity: $0.quantity, unitPrice: $0.unitPrice, kind: "service") }
        let included = pricing?.optionDetails[active.selections.pricingMode]?.includedLines ?? []
        lines += included.enumerated().map { index, line in HLQuoteLine(id: "\(activeID)-included-\(index)", name: line.name, description: line.description, unitPrice: 0, kind: "included") }
        return lines
    }
    func updateQuoteLines(_ update: (inout [HLQuoteLine]) -> Void) {
        var lines = quoteLines; update(&lines)
        edit(invalidatePreview: false) { option in
            var adjustment = option.selections.adjustments[option.selections.pricingMode] ?? HLAdjustment()
            adjustment.lineItems = lines; adjustment.price = nil; adjustment.partsPrice = nil; adjustment.laborPrice = nil
            option.selections.adjustments[option.selections.pricingMode] = adjustment
            option.selections.services = []; option.selections.reinstallPrice = nil
        }
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
                    customerID = visit.customer?.id; propertyID = visit.property?.id ?? initialPropertyID; customerName = visit.customer?.name ?? ""
                    address = visit.property?.address ?? visit.address ?? ""; city = visit.property?.city ?? visit.city ?? ""; state = visit.property?.state ?? visit.state ?? ""; zip = visit.property?.zip ?? visit.zip ?? ""
                    if let lat = visit.property?.latitude, let lng = visit.property?.longitude { center = HLPoint(lat: lat, lng: lng) }
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
        pricingByOption = response.optionPricing ?? [:]
        if let pricing { pricingByOption[activeID] = pricing }
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
        if !dirty && quoteID != nil { return true }
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
        } catch {
            guard !Task.isCancelled else { return }
            do {
                let locations = try await CLGeocoder().geocodeAddressString([address, city, state, zip].filter { !$0.isEmpty }.joined(separator: ", "))
                if let point = locations.first?.location?.coordinate { center = HLPoint(point); dirty = true }
                else { self.error = "Could not locate this address. Check the street, city and ZIP." }
            } catch { self.error = "Could not locate this address. Check the street, city and ZIP." }
        }
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
                guard let image = UIImage(data: data) else { throw APIError.server("Could not open property photo") }
                photo = image
            } else {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.server("Could not load property photo") }
                guard let image = UIImage(data: data) else { throw APIError.server("Could not open property photo") }
                photo = image
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
    func streetView(api: APIClient, heading: Double, pitch: Double, pano: String = "") async {
        guard await save(api: api) else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let data = try await api.getData(path: path + "/photo", query: [URLQueryItem(name: "heading", value: String(heading)), URLQueryItem(name: "pitch", value: String(pitch)), URLQueryItem(name: "pano", value: pano)])
            guard let image = UIImage(data: data) else { throw APIError.server("No Street View photo found. Take or select a property photo instead.") }
            photo = image; photoUnsaved = true
            notice = nil
        } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
    }
    func generatePreview(api: APIClient) async {
        guard let photo else { error = "Choose a property photo first."; return }
        guard !active.markup.isEmpty else { error = "Paint the areas you want lit before generating."; return }
        guard sourcePhotoURL != nil, !photoUnsaved else { error = "Save the property photo before generating a preview."; return }
        guard await save(api: api) else { return }
        guard !generating else { return }
        generating = true; previewComplete = false; previewProgress = 0.2; previewStage = "Preparing photo"
        error = nil
        let optionID = activeID
        let snapshotEncoder = JSONEncoder(); snapshotEncoder.outputFormatting = .sortedKeys
        let snapshot = try? snapshotEncoder.encode(active)
        defer { generating = false }
        do {
            let clean = try HLPhotoRenderer.jpeg(photo)
            let marked = try HLPhotoRenderer.jpeg(photo, strokes: active.markup)
            guard clean.count + marked.count < 4 * 1024 * 1024 else { throw APIError.badRequest("Photo is too large. Select a smaller image.") }
            struct Preview: Decodable { let previewImageUrl: String }
            previewProgress = 0.4; previewStage = "Generating lighting preview"
            let preview: Preview = try await api.uploadImages(path: path + "/visualize", fields: ["optionId": optionID, "persistOptionPreview": "true"], images: [("clean", clean), ("marked", marked)], timeout: 290)
            previewProgress = 0.85; previewStage = "Saving preview"
            let response: HLQuoteResponse = try await api.get(path: path)
            updatedAt = response.quote.updatedAt
            if let index = options.firstIndex(where: { $0.id == optionID }),
               (try? snapshotEncoder.encode(options[index])) == snapshot {
                let hadLocalEdits = dirty
                options[index].previewURL = preview.previewImageUrl
                if !hadLocalEdits { dirty = false }
            }
            previewProgress = 1; previewStage = "Preview ready"; previewComplete = true
            try? await Task.sleep(for: .seconds(3))
            previewProgress = nil; previewComplete = false
        } catch {
            previewProgress = nil
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
