import SwiftUI

struct RachioPropertySection: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var auth: AuthManager
    let customerId: String
    let propertyId: String

    @State private var linked = false
    @State private var deviceName: String?
    @State private var zones: [RachioZoneDTO] = []
    @State private var runningZoneId: String?
    @State private var message: String?
    @State private var error: String?

    private var canControl: Bool {
        guard let role = auth.user?.role else { return false }
        return UserRoles.canEditVisitOfficeFields(role)
    }

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 10) {
                StormSectionHeader(title: "Rachio controller", systemImage: "drop.circle")

                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else if !linked {
                    Text("No Rachio device linked to this property.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    if let deviceName {
                        Text(deviceName).font(.subheadline.weight(.medium))
                    }
                    if let message {
                        Text(message).font(.caption).foregroundStyle(StormTheme.success)
                    }
                    ForEach(zones) { zone in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(zone.name ?? "Zone \(zone.zoneNumber.map(String.init) ?? "?")")
                                    .font(.subheadline)
                                if zone.enabled == false {
                                    Text("Disabled").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if canControl {
                                Button("Run 3m") {
                                    Task { await runZone(zone.id, minutes: 3) }
                                }
                                .buttonStyle(StormSecondaryButtonStyle())
                                .disabled(runningZoneId == zone.id)
                            }
                        }
                    }
                    if canControl {
                        Button("Stop all watering") {
                            Task { await stopAll() }
                        }
                        .buttonStyle(StormSecondaryButtonStyle())
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let response: RachioStatusResponse = try await env.apiClient.get(
                path: APIPath.rachio(customerId: customerId, propertyId: propertyId)
            )
            linked = response.linked
            deviceName = response.device?.name
            zones = response.device?.zones ?? []
        } catch {
            self.error = (error as? APIError)?.message
        }
    }

    private func runZone(_ zoneId: String, minutes: Int) async {
        runningZoneId = zoneId
        defer { runningZoneId = nil }
        struct Body: Encodable { let durationMinutes: Int }
        do {
            let _: RachioOkResponse = try await env.apiClient.put(
                path: APIPath.rachioStartZone(customerId: customerId, propertyId: propertyId, zoneId: zoneId),
                body: Body(durationMinutes: minutes)
            )
            message = "Zone started for \(minutes) minutes"
        } catch {
            self.error = (error as? APIError)?.message
        }
    }

    private func stopAll() async {
        do {
            let _: RachioOkResponse = try await env.apiClient.put(
                path: APIPath.rachioStop(customerId: customerId, propertyId: propertyId)
            )
            message = "Watering stopped"
        } catch {
            self.error = (error as? APIError)?.message
        }
    }
}

struct RachioStatusResponse: Decodable {
    let linked: Bool
    let device: RachioDeviceDTO?
}

struct RachioDeviceDTO: Decodable {
    let name: String?
    let zones: [RachioZoneDTO]?
}

struct RachioZoneDTO: Decodable, Identifiable {
    let id: String
    let name: String?
    let zoneNumber: Int?
    let enabled: Bool?
}

struct RachioOkResponse: Decodable {
    let ok: Bool?
}
