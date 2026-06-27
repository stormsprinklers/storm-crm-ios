import Foundation

struct ScheduleFiltersResponse: Decodable {
    let employees: [ScheduleEmployeeDTO]?
}

struct ScheduleEmployeeDTO: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let color: String?
    let photoUrl: String?
}

extension ScheduleEmployeeDTO {
    init(id: String, name: String, color: String?, photoUrl: String?) {
        self.id = id
        self.name = name
        self.color = color
        self.photoUrl = photoUrl
    }

    var namedColor: NamedColor {
        NamedColor(id: id, name: name, color: color, photoUrl: photoUrl)
    }
}

struct PriceBookItemDTO: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let unitPrice: Double
    let unit: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, unitPrice, unit, type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        unitPrice = try container.decodeFlexibleDouble(forKey: .unitPrice) ?? 0
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        type = try container.decodeIfPresent(String.self, forKey: .type)
    }
}

enum VisitDateEditing {
    static func date(from iso: String) -> Date {
        APIDateFormatting.parse(iso) ?? Date()
    }

    static func isoString(from date: Date) -> String {
        APIDateFormatting.queryString(from: date)
    }
}
