import Foundation

// Standalone checks compile the real model source, without a simulator or live CRM.
@main struct HolidayQuoteModelsChecks {
    static func main() throws {
        let segmentJSON = #"{"id":"run-a","label":"Front peak","kind":"roofline","path":[{"lat":40,"lng":-111},{"lat":40.0001,"lng":-111}],"lengthFt":20,"horizontalLengthFt":20,"hasPeak":true,"lightStyleKey":"c9","colorPattern":"Red / Green","legacyPitchMetadata":{"keep":true}}"#
        var segment = try JSONDecoder().decode(HLSegment.self, from: Data(segmentJSON.utf8))
        segment.length = 30
        let roundTrip = try JSONSerialization.jsonObject(with: JSONEncoder().encode(segment)) as! [String: Any]
        precondition(roundTrip["horizontalLengthFt"] as? Double == 30)
        precondition(roundTrip["lengthFt"] as? Double == 30)
        precondition((roundTrip["legacyPitchMetadata"] as? [String: Bool])?["keep"] == true)
        precondition(segment.path.count == 2 && segment.hasPeak && segment.color == "Red / Green")
        let legacyTree = HLPlacement(fields: ["size": .string("xl")])
        precondition(legacyTree.strands == 4)
        let legacyLabor = HLSelections(fields: ["billingMode": .string("labor_only")])
        precondition(legacyLabor.pricingMode == "labor")
        let feet = HLPoint.lengthFeet([HLPoint(lat: 0, lng: 0), HLPoint(lat: 0, lng: 0.001)])
        precondition(abs(feet - 364.8) < 0.2)
        precondition(HLPoint.lengthFeet([]) == 0)
        var measurements = HLMeasurements()
        measurements.segments = [segment]
        measurements.strands = [HLStrand(label: "Front", segments: [segment.id])]
        var first = HLDesign(label: "Buy", measurements: measurements)
        first.markup = [HLMarkupStroke(points: [HLMarkupPoint(x: 0.25, y: 0.75)])]
        first.previewURL = "https://example.com/option-a.jpg"
        first.selections.notes = "Keep existing clips"
        var second = first
        second.id = UUID().uuidString; second.label = "Lease"; second.selections.pricingMode = "lease"
        second.measurements.segments[0].color = "Warm White"
        let options = try JSONDecoder().decode([HLDesign].self, from: JSONEncoder().encode([first, second]))
        precondition(options[0].selections.pricingMode == "buy" && options[1].selections.pricingMode == "lease")
        precondition(options[0].measurements.segments[0].color == "Red / Green")
        precondition(options[1].measurements.segments[0].color == "Warm White")
        precondition(options[0].markup[0].points[0].x == 0.25)
        precondition(options[0].previewURL == "https://example.com/option-a.jpg")
        precondition(options[1].measurements.strands[0].segmentIDs == ["run-a"])
        var service = HLService(); service.name = "Wreath"; service.quantity = 2; service.unitPrice = 40
        var selections = HLSelections(); selections.services = [service]; selections.reinstallPrice = nil
        selections.style = "permanent"
        precondition(selections.pricingMode == "permanent")
        selections.style = "c7"
        precondition(selections.pricingMode == "buy")
        let selected = try JSONDecoder().decode(HLSelections.self, from: JSONEncoder().encode(selections))
        precondition(selected.services[0].quantity == 2 && selected.reinstallPrice == nil)
        if let path = CommandLine.arguments.dropFirst().first {
            var root = HLSelections()
            root.put("designOptions", options); root.put("activeDesignOptionId", options[1].id)
            var envelope = HLMeasurements()
            envelope.put("measurements", options[1].measurements); envelope.put("selections", root)
            try JSONEncoder().encode(envelope).write(to: URL(fileURLWithPath: path))
        }
        print("PASS: legacy fields, CRM-compatible measurements, independent options, photo markup, strands, and pricing selections")
    }
}
