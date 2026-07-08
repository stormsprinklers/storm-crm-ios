import Foundation

enum PhoneDialing {
    /// Best-effort E.164 normalization for US numbers before sending to Twilio.
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if trimmed.hasPrefix("+") {
            let digits = trimmed.dropFirst().filter(\.isNumber)
            return digits.isEmpty ? trimmed : "+\(digits)"
        }

        let digits = trimmed.filter(\.isNumber)
        if digits.count == 10 {
            return "+1\(digits)"
        }
        if digits.count == 11, digits.hasPrefix("1") {
            return "+\(digits)"
        }
        if !digits.isEmpty {
            return "+\(digits)"
        }
        return trimmed
    }
}
