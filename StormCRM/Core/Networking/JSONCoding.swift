import Foundation

enum JSONCoding {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // CRM API returns camelCase JSON (startAt, companyId, …).
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        JSONEncoder()
    }
}

/// Decodes JSON numbers or numeric strings (Prisma Decimal fields).
struct FlexibleDouble: Codable, Hashable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
            return
        }
        if let number = try? container.decode(Double.self) {
            value = number
            return
        }
        if let text = try? container.decode(String.self) {
            value = Double(text)
            return
        }
        value = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
    }
}

extension KeyedDecodingContainer {
    func decodeFlexibleDouble(forKey key: Key) throws -> Double? {
        if (try? decodeNil(forKey: key)) == true { return nil }
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let text = try? decode(String.self, forKey: key) { return Double(text) }
        return nil
    }
}

enum APIDateFormatting {
    static func queryString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// `yyyy-MM-dd` for reporting API custom ranges (matches web CRM).
    static func dateOnlyString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func displayString(from iso: String) -> String {
        guard let date = parse(iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func parse(_ iso: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: iso) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: iso) { return date }

        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return basic.date(from: iso)
    }
}
