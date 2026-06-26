import SwiftUI

struct IrrigationReadOnlyView: View {
    @EnvironmentObject private var env: AppEnvironment
    let customerId: String
    let propertyId: String
    let propertyName: String

    @State private var map: IrrigationMapDTO?
    @State private var program: IrrigationProgramDTO?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                if let imageUrl = map?.imageUrl, let url = URL(string: imageUrl) {
                    Text("Zone map").font(.headline)
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if let zones = map?.zones, !zones.isEmpty {
                    Text("Zones").font(.headline)
                    ForEach(zones) { zone in
                        HStack {
                            Circle().fill(Color(hex: zone.color) ?? .blue).frame(width: 12, height: 12)
                            Text(zone.label ?? zone.id)
                        }
                    }
                }
                if let programZones = program?.zones, !programZones.isEmpty {
                    Text("Program guide").font(.headline)
                    ForEach(programZones) { zone in
                        VStack(alignment: .leading) {
                            Text(zone.name ?? "Zone").font(.subheadline.bold())
                            if let times = zone.runTimes {
                                Text(times.joined(separator: ", ")).font(.caption)
                            }
                        }
                    }
                }
                if let notes = program?.notes, !notes.isEmpty {
                    Text(notes).font(.body)
                }
            }
            .padding()
        }
        .navigationTitle(propertyName)
        .task { await load() }
    }

    private func load() async {
        do {
            map = try await env.apiClient.get(path: APIPath.irrigationMap(customerId: customerId, propertyId: propertyId))
            program = try await env.apiClient.get(path: APIPath.irrigationProgram(customerId: customerId, propertyId: propertyId))
        } catch {
            self.error = (error as? APIError)?.message
        }
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count >= 7 else { return nil }
        let start = hex.index(hex.startIndex, offsetBy: 1)
        let r = Int(hex[start..<hex.index(start, offsetBy: 2)], radix: 16) ?? 0
        let g = Int(hex[hex.index(start, offsetBy: 2)..<hex.index(start, offsetBy: 4)], radix: 16) ?? 0
        let b = Int(hex[hex.index(start, offsetBy: 4)..<hex.index(start, offsetBy: 6)], radix: 16) ?? 0
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}
