import Foundation
import CoreLocation

// JSON-backed records preserve legacy CRM fields when a design is edited on iOS.
protocol HLRecord: Codable {
    var fields: [String: JSONValue] { get set }
    init(fields: [String: JSONValue])
}
extension HLRecord {
    init(from decoder: Decoder) throws { self.init(fields: try decoder.singleValueContainer().decode([String: JSONValue].self)) }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(fields) }
    func value<T: Decodable>(_ key: String, fallback: T) -> T {
        guard let raw = fields[key], let data = try? JSONEncoder().encode(raw), let result = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return result
    }
    mutating func put<T: Encodable>(_ key: String, _ value: T) {
        guard let data = try? JSONEncoder().encode(value), let raw = try? JSONDecoder().decode(JSONValue.self, from: data) else { return }
        fields[key] = raw
    }
}
struct HLPoint: Codable, Equatable {
    var lat: Double
    var lng: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }
    init(lat: Double, lng: Double) { self.lat = lat; self.lng = lng }
    init(_ coordinate: CLLocationCoordinate2D) { lat = coordinate.latitude; lng = coordinate.longitude }
    static func lengthFeet(_ path: [HLPoint]) -> Double {
        guard path.count > 1 else { return 0 }
        let radius = 20_902_231.0
        let total = zip(path, path.dropFirst()).reduce(0.0) { total, pair in
            let (a, b) = pair
            let lat1 = a.lat * .pi / 180, lat2 = b.lat * .pi / 180
            let dLat = lat2 - lat1, dLng = (b.lng - a.lng) * .pi / 180
            let h = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLng / 2), 2)
            return total + 2 * radius * asin(min(1, sqrt(h)))
        }
        return (total * 10).rounded() / 10
    }
}
struct HLSegment: HLRecord, Identifiable {
    var fields: [String: JSONValue] = [:]
    var id: String { value("id", fallback: "") }
    var label: String { get { value("label", fallback: "Roofline") } set { put("label", newValue) } }
    var kind: String { get { value("kind", fallback: "roofline") } set { put("kind", newValue) } }
    var path: [HLPoint] { get { value("path", fallback: []) } set { put("path", newValue) } }
    var length: Double { get { value("horizontalLengthFt", fallback: value("lengthFt", fallback: 0.0)) } set { put("lengthFt", max(0, newValue)); put("horizontalLengthFt", max(0, newValue)) } }
    var hasPeak: Bool { get { value("hasPeak", fallback: false) } set { put("hasPeak", newValue) } }
    var style: String { get { value("lightStyleKey", fallback: "c9") } set { put("lightStyleKey", newValue) } }
    var color: String { get { value("colorPattern", fallback: "Warm White") } set { put("colorPattern", newValue) } }
    init(fields: [String: JSONValue]) { self.fields = fields }
    init(path: [HLPoint], style: String, color: String, count: Int) {
        put("id", UUID().uuidString); label = "Roofline \(count)"; kind = "roofline"
        self.path = path; length = HLPoint.lengthFeet(path); self.style = style; self.color = color
    }
}
struct HLPlacement: HLRecord, Identifiable {
    var fields: [String: JSONValue] = [:]
    var id: String { value("id", fallback: "") }
    var label: String { get { value("label", fallback: "Tree") } set { put("label", newValue) } }
    var kind: String { get { value("kind", fallback: "tree") } set { put("kind", newValue) } }
    var point: HLPoint { get { value("latLng", fallback: HLPoint(lat: 0, lng: 0)) } set { put("latLng", newValue) } }
    var strands: Int { get { value("strandCount", fallback: ["small": 1, "medium": 2, "large": 3, "xl": 4][value("size", fallback: "small")] ?? 1) } set { put("strandCount", min(100, max(1, newValue))) } }
    var difficulty: Int { get { value("difficulty", fallback: 1) } set { put("difficulty", min(3, max(1, newValue))) } }
    var lift: Bool { get { value("liftRentalNeeded", fallback: false) } set { put("liftRentalNeeded", newValue) } }
    var style: String { get { value("lightStyleKey", fallback: "mini") } set { put("lightStyleKey", newValue) } }
    var color: String { get { value("colorPattern", fallback: "Warm White") } set { put("colorPattern", newValue) } }
    init(fields: [String: JSONValue]) { self.fields = fields }
    init(kind: String, point: HLPoint, color: String, count: Int) {
        put("id", UUID().uuidString); put("size", "small"); self.kind = kind; self.point = point
        label = "\(kind.capitalized) \(count)"; strands = 1; difficulty = 1; style = "mini"; self.color = color
    }
}
struct HLStrand: HLRecord, Identifiable {
    var fields: [String: JSONValue] = [:]
    var id: String { value("id", fallback: "") }
    var label: String { get { value("label", fallback: "Strand") } set { put("label", newValue) } }
    var segmentIDs: [String] { get { value("segmentIds", fallback: []) } set { put("segmentIds", newValue) } }
    init(fields: [String: JSONValue]) { self.fields = fields }
    init(label: String, segments: [String]) { put("id", UUID().uuidString); self.label = label; segmentIDs = segments }
}
struct HLMeasurements: HLRecord {
    var fields: [String: JSONValue] = [:]
    var segments: [HLSegment] { get { value("segments", fallback: []) } set { put("segments", newValue) } }
    var placements: [HLPlacement] { get { value("placements", fallback: []) } set { put("placements", newValue) } }
    var strands: [HLStrand] { get { value("strands", fallback: []) } set { put("strands", newValue) } }
}
struct HLService: HLRecord, Identifiable {
    var fields: [String: JSONValue] = [:]
    var id: String { value("id", fallback: "") }
    var name: String { get { value("name", fallback: "") } set { put("name", newValue) } }
    var detail: String { get { value("description", fallback: "") } set { put("description", newValue) } }
    var quantity: Double { get { value("quantity", fallback: 1.0) } set { put("quantity", max(0, newValue)) } }
    var unitPrice: Double { get { value("unitPrice", fallback: 0.0) } set { put("unitPrice", max(0, newValue)) } }
    init(fields: [String: JSONValue]) { self.fields = fields }
    init() { put("id", UUID().uuidString); quantity = 1 }
}
struct HLSelections: HLRecord {
    var fields: [String: JSONValue] = [:]
    var style: String { get { value("defaultLightStyleKey", fallback: "c9") } set { put("defaultLightStyleKey", newValue); put("installKind", newValue == "permanent" ? "permanent" : "temporary"); if newValue == "permanent" { pricingMode = "permanent" } else if pricingMode == "permanent" { pricingMode = "buy" } } }
    var color: String { get { value("defaultColorPattern", fallback: "Warm White") } set { put("defaultColorPattern", newValue) } }
    var pricingMode: String { get { value("pricingMode", fallback: style == "permanent" ? "permanent" : value("billingMode", fallback: "standard") == "labor_only" ? "labor" : "buy") } set { put("pricingMode", newValue); put("billingMode", "standard") } }
    var completedSteps: [String] { get { value("completedSteps", fallback: []) } set { put("completedSteps", newValue) } }
    var notes: String { get { value("notes", fallback: "") } set { put("notes", newValue) } }
    var leaseYears: Int { get { value("leaseContractYears", fallback: 1) } set { put("leaseContractYears", newValue) } }
    var services: [HLService] { get { value("customServices", fallback: []) } set { put("customServices", newValue) } }
    var adjustments: [String: HLAdjustment] { get { value("optionAdjustments", fallback: [:]) } set { put("optionAdjustments", newValue) } }
    var reinstallPrice: Double? { get { value("reinstallPrice", fallback: Optional<Double>.none) } set { put("reinstallPrice", newValue) } }
}
struct HLAdjustment: Codable {
    var lineItems: [HLQuoteLine]?
    var partsPrice: Double?
    var laborPrice: Double?
    var price: Double?
    var discountLabel: String?
    var discountType: String?
    var discountAmount: Double?
}
struct HLMarkupPoint: Codable { var x: Double; var y: Double }
struct HLMarkupStroke: Codable, Identifiable {
    var id = UUID().uuidString
    var points: [HLMarkupPoint] = []
    var color = "#ffb020"
    var width = 0.012
}
struct HLDesign: HLRecord, Identifiable {
    var fields: [String: JSONValue] = [:]
    var id: String { get { value("id", fallback: "") } set { put("id", newValue) } }
    var label: String { get { value("label", fallback: "Option 1") } set { put("label", newValue) } }
    var measurements: HLMeasurements { get { value("measurements", fallback: HLMeasurements()) } set { put("measurements", newValue) } }
    var selections: HLSelections { get { value("selections", fallback: HLSelections()) } set { put("selections", newValue) } }
    var previewURL: String? { get { value("previewImageUrl", fallback: Optional<String>.none) } set { put("previewImageUrl", newValue) } }
    var markup: [HLMarkupStroke] { get { value("photoMarkup", fallback: []) } set { put("photoMarkup", newValue) } }
    init(fields: [String: JSONValue]) { self.fields = fields }
    init(label: String = "Option 1", measurements: HLMeasurements = .init(), selections: HLSelections = .init()) {
        id = UUID().uuidString; self.label = label; self.measurements = measurements; self.selections = selections
    }
}
struct HLQuote: Decodable, Identifiable {
    let id: String
    let customerId: String?
    let propertyId: String?
    let visitId: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let lat: Double?
    let lng: Double?
    let sourcePhotoUrl: String?
    let previewImageUrl: String?
    let measurements: HLMeasurements
    let selections: HLSelections
    let status: String
    let updatedAt: String
    struct Customer: Decodable { let id: String; let name: String }
    struct Estimate: Decodable { let id: String; let estimateNumber: String?; let status: String }
    let customer: Customer?
    let estimate: Estimate?
    var title: String { customer?.name ?? [address, city].compactMap { $0 }.joined(separator: ", ") }
}
struct HLCatalog: Decodable {
    struct Style: Decodable, Identifiable { let key: String; let label: String; let kind: String?; var id: String { key } }
    struct Defaults: Decodable { let defaultLightStyleKey: String; let defaultInstallKind: String }
    let lightStyles: [Style]
    let quoteDefaults: Defaults?
}
struct HLPricing: Decodable {
    struct DisplayLine: Decodable { let name: String; let description: String; let total: Double }
    struct Detail: Decodable { let displayLines: [DisplayLine]?; let includedLines: [DisplayLine]?; let partsPrice: Double?; let laborPrice: Double?; let calculated: Double; let subtotal: Double; let discountTotal: Double; let total: Double }
    struct Line: Decodable, Identifiable { let key: String; let name: String; let staffDetail: String; let purchaseTotal: Double; let leaseTotal: Double; let partsTotal: Double; let laborTotal: Double; var id: String { key } }
    let billedLengthFt: Double
    let reinstallTotal: Double
    let year1MinimumApplied: Bool
    let permanentMinimumApplied: Bool
    let optionDetails: [String: Detail]
    let lines: [Line]
}
struct HLQuoteResponse: Decodable { let quote: HLQuote; let catalog: HLCatalog?; let pricing: HLPricing?; let optionPricing: [String: HLPricing]? }
struct HLQuoteListResponse: Decodable { let quotes: [HLQuote] }
struct HLCatalogResponse: Decodable { let catalog: HLCatalog }

let holidayBulbColors = ["Warm White", "Winter White", "Champagne", "Red", "Green", "Blue", "Yellow", "Pink", "Orange", "Other"]

struct HLQuoteLine: Codable, Identifiable {
    var id: String
    var name: String
    var description: String
    var quantity: Double = 1
    var unitPrice: Double
    var kind: String
    var total: Double { kind == "included" ? 0 : (quantity * unitPrice * 100).rounded() / 100 }
}

struct HLQuoteDraftSnapshot: Codable {
    let customerID: String?
    let propertyID: String?
    let address: [String]
    let center: HLPoint?
    let options: [HLDesign]
    func encoded() -> Data? { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try? encoder.encode(self) }
}
