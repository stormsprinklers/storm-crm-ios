import SwiftUI
import MapKit

private struct HolidayPlan: Decodable {
    struct Point: Decodable { let lat: Double; let lng: Double; var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) } }
    struct Feature: Decodable, Identifiable {
        let id: String
        let label: String
        let color: String
        let paths: [[Point]]
        let lightStyleLabel: String
        let bulbColors: String?
        struct Placement: Decodable { let latLng: Point; let radiusMeters: Double }
        let placement: Placement?
        let lengthFtWithMargin: Double
    }
    let features: [Feature]
}

struct HolidayVisitPlanSection: View {
    let metadata: JSONValue?
    private var plan: HolidayPlan? {
        guard let value = metadata?["strandMap"], let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(HolidayPlan.self, from: data)
    }
    var body: some View {
        if let plan, !plan.features.isEmpty {
            StormCard {
                VStack(alignment: .leading, spacing: 12) {
                    StormSectionHeader(title: "Holiday lighting plan", systemImage: "lightbulb.2")
                    Map {
                        ForEach(plan.features) { feature in
                            ForEach(Array(feature.paths.enumerated()), id: \.offset) { _, path in
                                MapPolyline(coordinates: path.map(\.coordinate)).stroke(Color(hex: feature.color) ?? .orange, lineWidth: 4)
                            }
                            if let placement = feature.placement { MapCircle(center: placement.latLng.coordinate, radius: placement.radiusMeters).foregroundStyle((Color(hex: feature.color) ?? .orange).opacity(0.4)) }
                            if let point = feature.paths.first?.first ?? feature.placement?.latLng {
                                Annotation(feature.label, coordinate: point.coordinate) {
                                    Circle().fill(Color(hex: feature.color) ?? .orange).frame(width: 10, height: 10)
                                }
                            }
                        }
                    }.mapStyle(.imagery).frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 8))
                    ForEach(plan.features) { feature in
                        HStack(alignment: .top) {
                            Circle().fill(Color(hex: feature.color) ?? .orange).frame(width: 10, height: 10).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feature.label).font(.subheadline.bold())
                                Text(feature.lightStyleLabel).font(.caption)
                                Text("Bulb colors: \(feature.bulbColors ?? "Not specified in approved quote")").font(.caption).foregroundStyle(.secondary)
                                Text("\(feature.lengthFtWithMargin, specifier: "%.1f") ft including margin").font(.caption)
                            }
                        }
                    }
                }
            }
        } else {
            StormCard {
                VStack(alignment: .leading, spacing: 8) {
                    StormSectionHeader(title: "Bulb types and colors", systemImage: "lightbulb.2")
                    Text("Create or approve a holiday lighting quote to attach the home's aerial strand map, bulb types, and colors.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}
