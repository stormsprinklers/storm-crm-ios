import SwiftUI

struct RachioPropertySection: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var auth: AuthManager
    let customerId: String
    let propertyId: String
    var embedded: Bool = false

    @State private var linked = false
    @State private var deviceName: String?
    @State private var zones: [RachioZoneDTO] = []
    @State private var runningZoneId: String?
    @State private var message: String?
    @State private var error: String?

    @State private var showLinkSheet = false
    @State private var devices: [RachioDeviceSummaryDTO] = []
    @State private var selectedDeviceId = ""
    @State private var devicesLoading = false
    @State private var devicesError: String?
    @State private var linking = false
    @State private var unlinking = false

    private var canManage: Bool {
        guard let role = auth.user?.role else { return false }
        return UserRoles.canLinkRachio(role)
    }

    private var canControl: Bool {
        guard let role = auth.user?.role else { return false }
        return UserRoles.canControlRachio(role)
    }

    private var isOnline: Bool {
        env.offlineSync.isOnline
    }

    var body: some View {
        Group {
            if embedded {
                sectionContent
            } else {
                StormCard { sectionContent }
            }
        }
        .task(id: propertyId) { await load() }
        .sheet(isPresented: $showLinkSheet) {
            RachioLinkDeviceSheet(
                devices: $devices,
                selectedDeviceId: $selectedDeviceId,
                devicesLoading: $devicesLoading,
                devicesError: $devicesError,
                linking: $linking,
                linkError: error,
                onLoadDevices: { await loadDevices() },
                onLink: { await linkDevice() }
            )
            .environmentObject(env)
        }
    }

    private var sectionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isOnline {
                Text("Rachio controls need an internet connection.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if !linked {
                if canManage, isOnline {
                    Button {
                        showLinkSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image("RachioLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text("Rachio")
                                .font(.body.weight(.semibold))
                            Text("+")
                                .font(.title3.weight(.bold))
                        }
                        .foregroundStyle(StormTheme.navy)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(StormTheme.ice.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(StormTheme.sky.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rachio plus, link device")
                } else {
                    Text("No Rachio device linked to this property.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 10) {
                    Image("RachioLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rachio")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(StormTheme.navy)
                        if let deviceName {
                            Text(deviceName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
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
                        if canControl, isOnline {
                            Button("Run 3m") {
                                Task { await runZone(zone.id, minutes: 3) }
                            }
                            .buttonStyle(StormSecondaryButtonStyle())
                            .disabled(runningZoneId == zone.id)
                        }
                    }
                }
                if canControl || canManage {
                    HStack(spacing: 10) {
                        if canControl, isOnline {
                            Button("Stop all watering") {
                                Task { await stopAll() }
                            }
                            .buttonStyle(StormSecondaryButtonStyle())
                        }

                        if canManage, isOnline {
                            Button("Unlink") {
                                Task { await unlinkDevice() }
                            }
                            .buttonStyle(StormSecondaryButtonStyle())
                            .disabled(unlinking)
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        error = nil
        do {
            let response: RachioStatusResponse = try await env.apiClient.get(
                path: APIPath.rachio(customerId: customerId, propertyId: propertyId)
            )
            linked = response.linked
            deviceName = response.device?.name
            zones = response.device?.zones ?? []
            if linked {
                selectedDeviceId = ""
            }
        } catch {
            self.error = (error as? APIError)?.message
        }
    }

    private func loadDevices() async {
        devicesLoading = devices.isEmpty
        devicesError = nil
        defer { devicesLoading = false }
        do {
            let response: RachioDevicesResponse = try await env.apiClient.get(
                path: APIPath.settingsRachioDevices
            )
            devices = response.devices ?? []
            if selectedDeviceId.isEmpty, devices.count == 1 {
                selectedDeviceId = devices[0].id
            }
        } catch {
            devicesError = (error as? APIError)?.message
                ?? "Failed to load Rachio devices. Configure your Rachio API key in CRM settings."
            devices = []
        }
    }

    private func linkDevice() async {
        guard !selectedDeviceId.isEmpty else { return }
        linking = true
        defer { linking = false }
        error = nil
        message = nil

        let selected = devices.first { $0.id == selectedDeviceId }
        struct Body: Encodable {
            let deviceId: String
            let deviceKind: String?
        }
        let body = Body(
            deviceId: selectedDeviceId,
            deviceKind: selected?.deviceKind
        )

        do {
            let _: RachioLinkResponse = try await env.apiClient.post(
                path: APIPath.rachioLink(customerId: customerId, propertyId: propertyId),
                body: body
            )
            message = "Rachio device linked"
            showLinkSheet = false
            await load()
        } catch {
            self.error = (error as? APIError)?.message
        }
    }

    private func unlinkDevice() async {
        unlinking = true
        defer { unlinking = false }
        error = nil
        message = nil
        do {
            try await env.apiClient.delete(
                path: APIPath.rachioLink(customerId: customerId, propertyId: propertyId)
            )
            zones = []
            deviceName = nil
            linked = false
            message = "Rachio device unlinked"
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

/// Sheet opened from the Rachio + button to pick and link a company device.
private struct RachioLinkDeviceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var devices: [RachioDeviceSummaryDTO]
    @Binding var selectedDeviceId: String
    @Binding var devicesLoading: Bool
    @Binding var devicesError: String?
    @Binding var linking: Bool
    var linkError: String?
    var onLoadDevices: () async -> Void
    var onLink: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image("RachioLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text("Link a Rachio device to this property.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Device") {
                    if devicesLoading {
                        ProgressView("Loading Rachio devices…")
                    } else if let devicesError {
                        Text(devicesError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if devices.isEmpty {
                        Text("No Rachio devices found on your company account.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Device", selection: $selectedDeviceId) {
                            Text("Select a device").tag("")
                            ForEach(devices) { device in
                                Text(device.pickerLabel).tag(device.id)
                            }
                        }
                    }
                }

                if let linkError {
                    Section {
                        Text(linkError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Rachio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(linking ? "Linking…" : "Link") {
                        Task { await onLink() }
                    }
                    .disabled(linking || selectedDeviceId.isEmpty || devicesLoading)
                }
            }
            .task { await onLoadDevices() }
        }
    }
}

struct RachioDevicesResponse: Decodable {
    let devices: [RachioDeviceSummaryDTO]?
}

struct RachioDeviceSummaryDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let serialNumber: String?
    let model: String?
    let status: String?
    let zoneCount: Int?
    let kind: String?

    var deviceKind: String? {
        guard let kind, kind == "hose_timer" else { return nil }
        return "hose_timer"
    }

    var pickerLabel: String {
        var parts = [name]
        if let serialNumber, !serialNumber.isEmpty {
            parts.append(serialNumber)
        }
        if let status, !status.isEmpty {
            parts.append("(\(status))")
        }
        return parts.joined(separator: " · ")
    }
}

struct RachioStatusResponse: Decodable {
    let linked: Bool
    let device: RachioDeviceDTO?
}

struct RachioLinkResponse: Decodable {
    let link: RachioLinkDTO?
    let device: RachioDeviceDTO?
}

struct RachioLinkDTO: Decodable {
    let id: String?
    let externalDeviceId: String?
    let status: String?
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
