import SwiftUI

struct PropertyIrrigationInlineSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let customerId: String
    let propertyId: String
    let propertyName: String
    let fallbackAerialUrl: String?
    var showsEditLink: Bool = false

    @State private var mapProperty: IrrigationMapProperty?
    @State private var programGuide: ControllerProgramGuideDTO?
    @State private var isLoading = true
    @State private var error: String?

    private var zones: [IrrigationMapZoneDTO] {
        mapProperty?.irrigationMapZones ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StormSectionHeader(title: "Irrigation map & program", systemImage: "drop.fill")

            if isLoading {
                ProgressView("Loading irrigation…")
            } else if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            } else {
                IrrigationMapCanvas(
                    imageUrl: mapProperty?.displayImageUrl ?? fallbackAerialUrl,
                    zones: zones,
                    markers: mapProperty?.allMarkersForDisplay() ?? [],
                    allowsZoom: true
                )

                Text("Pinch to zoom the map. Double-tap to reset.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if !zones.isEmpty {
                    IrrigationZoneLegend(zones: zones)
                } else {
                    Text("No zone boundaries drawn yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                IrrigationPropertyDetailsTable(
                    zoneCount: mapProperty?.irrigationZoneCount ?? (zones.isEmpty ? nil : zones.count),
                    shutoff: mapProperty?.shutoffValveLocation,
                    controller: mapProperty?.controllerLocation,
                    waterSource: mapProperty?.waterSource
                )

                if let guide = programGuide {
                    Divider()
                    Text("Controller program guide").font(.subheadline.bold())
                    IrrigationProgramGuideView(guide: guide)
                }

                if showsEditLink {
                    NavigationLink {
                        IrrigationMapEditorView(
                            customerId: customerId,
                            propertyId: propertyId,
                            propertyName: propertyName
                        )
                    } label: {
                        Label("Edit irrigation map", systemImage: "pencil")
                            .font(.subheadline)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .task(id: propertyId) { await load() }
    }

    private func load() async {
        isLoading = mapProperty == nil
        error = nil
        defer { isLoading = false }
        do {
            let mapResponse: IrrigationMapResponse = try await env.apiClient.get(
                path: APIPath.irrigationMap(customerId: customerId, propertyId: propertyId)
            )
            mapProperty = mapResponse.property
            let programResponse: IrrigationProgramResponse = try await env.apiClient.get(
                path: APIPath.irrigationProgram(customerId: customerId, propertyId: propertyId)
            )
            programGuide = programResponse.guide
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

/// Compact label/value rows for property irrigation details (no Form spacing).
struct IrrigationPropertyDetailsTable: View {
    var zoneCount: Int?
    var shutoff: String?
    var controller: String?
    var waterSource: String?

    private var rows: [(String, String)] {
        var result: [(String, String)] = []
        if let zoneCount, zoneCount > 0 {
            result.append(("Irrigation zones", "\(zoneCount)"))
        }
        if let shutoff, !shutoff.isEmpty {
            result.append(("Shutoff", shutoff))
        }
        if let controller, !controller.isEmpty {
            result.append(("Controller", controller))
        }
        if let waterSource, !waterSource.isEmpty {
            result.append(("Water source", waterSource))
        }
        return result
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.0)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        Text(row.1)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                    if index < rows.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(StormTheme.ice.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct VisitPropertyIrrigationPreview: View {
    @EnvironmentObject private var env: AppEnvironment
    let customerId: String
    let property: PropertySummary

    @State private var mapProperty: IrrigationMapProperty?
    @State private var isLoading = true
    @State private var error: String?

    private var zones: [IrrigationMapZoneDTO] {
        mapProperty?.irrigationMapZones ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Irrigation map")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if mapProperty?.irrigationMapStatus == "PUBLISHED" {
                    StormBadge(text: "Published", style: .success)
                }
            }

            if isLoading {
                ProgressView("Loading map…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                IrrigationMapCanvas(
                    imageUrl: mapProperty?.displayImageUrl ?? property.aerialImageUrl,
                    zones: zones,
                    markers: mapProperty?.allMarkersForDisplay() ?? [],
                    allowsZoom: true,
                    focusOnZones: true
                )

                if !zones.isEmpty {
                    IrrigationZoneLegend(zones: zones)
                } else {
                    Text("No zone boundaries drawn yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Pinch to zoom the map. Double-tap to reset.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: property.id) { await load() }
    }

    private func load() async {
        isLoading = mapProperty == nil
        error = nil
        defer { isLoading = false }
        do {
            let mapResponse: IrrigationMapResponse = try await env.apiClient.get(
                path: APIPath.irrigationMap(customerId: customerId, propertyId: property.id)
            )
            mapProperty = mapResponse.property
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct VisitIrrigationSection: View {
    let customerId: String
    let property: PropertySummary

    var body: some View {
        StormCard {
            PropertyIrrigationInlineSection(
                customerId: customerId,
                propertyId: property.id,
                propertyName: property.name ?? "Property",
                fallbackAerialUrl: property.aerialImageUrl,
                showsEditLink: true
            )
        }
    }
}

struct IrrigationDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    let customerId: String
    let propertyId: String
    let propertyName: String

    @State private var mapProperty: IrrigationMapProperty?
    @State private var programGuide: ControllerProgramGuideDTO?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error {
                    Text(error).foregroundStyle(.red)
                }

                if let property = mapProperty {
                    HStack {
                        if property.irrigationMapStatus == "PUBLISHED" {
                            StormBadge(text: "Published", style: .success)
                        } else {
                            StormBadge(text: "Draft", style: .neutral)
                        }
                        Spacer()
                        NavigationLink {
                            IrrigationMapEditorView(
                                customerId: customerId,
                                propertyId: propertyId,
                                propertyName: propertyName
                            )
                        } label: {
                            Label("Edit map", systemImage: "pencil")
                        }
                        .buttonStyle(StormPrimaryButtonStyle())
                    }

                    IrrigationMapCanvas(
                        imageUrl: property.displayImageUrl,
                        zones: property.irrigationMapZones ?? [],
                        markers: property.allMarkersForDisplay(),
                        allowsZoom: true,
                        focusOnZones: true
                    )

                    if let zones = property.irrigationMapZones, !zones.isEmpty {
                        IrrigationZoneLegend(zones: zones)
                    }

                    IrrigationPropertyDetailsTable(
                        zoneCount: property.irrigationZoneCount
                            ?? (property.irrigationMapZones?.isEmpty == false
                                ? property.irrigationMapZones?.count
                                : nil),
                        shutoff: property.shutoffValveLocation,
                        controller: property.controllerLocation,
                        waterSource: property.waterSource
                    )

                    if let diagram = property.propertyDiagramUrl, diagram != property.aerialImageUrl {
                        Text("Property diagram").font(.headline)
                        AuthenticatedBlobImage(urlString: diagram)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                if let guide = programGuide {
                    StormCard {
                        VStack(alignment: .leading, spacing: 8) {
                            StormSectionHeader(title: "Controller program guide", systemImage: "clock")
                            IrrigationProgramGuideView(guide: guide)
                        }
                    }
                }

                RachioPropertySection(customerId: customerId, propertyId: propertyId)
            }
            .padding()
        }
        .background(StormTheme.page.ignoresSafeArea())
        .navigationTitle(propertyName)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            let mapResponse: IrrigationMapResponse = try await env.apiClient.get(
                path: APIPath.irrigationMap(customerId: customerId, propertyId: propertyId)
            )
            mapProperty = mapResponse.property
            let programResponse: IrrigationProgramResponse = try await env.apiClient.get(
                path: APIPath.irrigationProgram(customerId: customerId, propertyId: propertyId)
            )
            programGuide = programResponse.guide
            error = nil
        } catch {
            self.error = (error as? APIError)?.message
        }
    }
}

typealias IrrigationReadOnlyView = IrrigationDetailView
