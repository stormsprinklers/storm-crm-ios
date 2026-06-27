import Foundation

enum IrrigationConstants {
    struct LabeledOption: Identifiable, Hashable {
        let value: String
        let label: String
        var id: String { value }
    }

    static let vegetationTypes: [LabeledOption] = [
        .init(value: "grass", label: "Grass"),
        .init(value: "shrubs", label: "Shrubs"),
        .init(value: "trees", label: "Trees"),
        .init(value: "flower_bed", label: "Flower Bed"),
    ]

    static let shadeLevels: [LabeledOption] = [
        .init(value: "full_sun", label: "Full Sun"),
        .init(value: "some_shade", label: "Some Shade"),
        .init(value: "lots_of_shade", label: "Lots of Shade"),
    ]

    static let slopeLevels: [LabeledOption] = [
        .init(value: "flat", label: "Flat"),
        .init(value: "moderate", label: "Moderate"),
        .init(value: "steep", label: "Steep"),
    ]

    static let soilTypes: [LabeledOption] = [
        .init(value: "sand", label: "Sand"),
        .init(value: "clay", label: "Clay"),
        .init(value: "loam", label: "Loam"),
    ]

    static let irrigationTypes: [LabeledOption] = [
        .init(value: "spray", label: "Spray"),
        .init(value: "rotary", label: "Rotary"),
        .init(value: "rotor", label: "Rotor"),
        .init(value: "drip", label: "Drip Emitter"),
        .init(value: "bubbler", label: "Bubbler"),
    ]

    static let establishmentStages: [LabeledOption] = [
        .init(value: "NORMAL", label: "Established"),
        .init(value: "NEW_SOD", label: "New sod"),
        .init(value: "NEW_SEED", label: "New seed"),
    ]

    static let waterSources: [LabeledOption] = [
        .init(value: "SECONDARY", label: "Secondary water"),
        .init(value: "CULINARY", label: "Culinary water"),
        .init(value: "BOTH", label: "Both"),
    ]

    static let grassSeasons: [LabeledOption] = [
        .init(value: "COOL", label: "Cool season"),
        .init(value: "WARM", label: "Warm season"),
    ]

    static let markerKinds: [(type: String, label: String, color: String, short: String)] = [
        ("POC", "POC", "#2563EB", "P"),
        ("TIMER", "Timer", "#7C3AED", "T"),
        ("VALVE", "Valve", "#DC2626", "V"),
        ("FILTER", "Filter", "#059669", "F"),
        ("BACKFLOW", "Backflow", "#D97706", "B"),
    ]

    static func markerStyle(for type: String) -> (label: String, color: String, short: String) {
        if let match = markerKinds.first(where: { $0.type == type }) {
            return (match.label, match.color, match.short)
        }
        return (type, "#64748B", "?")
    }

    static func defaultGpm(for irrigationType: String) -> Double {
        switch irrigationType {
        case "spray": return 1.85
        case "rotary": return 0.48
        case "rotor": return 3.09
        case "drip": return 0.01
        case "bubbler": return 0.25
        default: return 1.85
        }
    }

    static func resolveZoneGpm(
        irrigationType: String,
        nozzleCount: Int,
        estimatedGpm: Double?,
        nozzleGpm: Double?
    ) -> Double {
        if let estimatedGpm, estimatedGpm > 0 {
            return (estimatedGpm * 100).rounded() / 100
        }
        let count = max(1, nozzleCount)
        let perHead = nozzleGpm ?? defaultGpm(for: irrigationType)
        return (Double(count) * perHead * 100).rounded() / 100
    }
}
