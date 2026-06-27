import SwiftUI

struct VisitIrrigationSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let customerId: String
    let property: PropertySummary

    @State private var mapProperty: IrrigationMapProperty?
    @State private var programGuide: ControllerProgramGuideDTO?
    @State private var isLoading = true
    @State private var error: String?

    private var zones: [IrrigationMapZoneDTO] {
        mapProperty?.irrigationMapZones ?? []
    }

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    StormSectionHeader(title: "Irrigation map & program", systemImage: "drop.fill")
                    Spacer()
                    if mapProperty?.irrigationMapStatus == "PUBLISHED" {
                        StormBadge(text: "Published", style: .success)
                    }
                }

                if isLoading {
                    ProgressView("Loading irrigation…")
                } else if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                } else {
                    IrrigationMapCanvas(
                        imageUrl: mapProperty?.displayImageUrl ?? property.aerialImageUrl,
                        zones: zones,
                        markers: mapProperty?.allMarkersForDisplay() ?? []
                    )

                    if !zones.isEmpty {
                        IrrigationZoneLegend(zones: zones)
                    } else {
                        Text("No zone boundaries drawn yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let shutoff = mapProperty?.shutoffValveLocation, !shutoff.isEmpty {
                        LabeledContent("Shutoff") { Text(shutoff).font(.caption) }
                    }
                    if let controller = mapProperty?.controllerLocation, !controller.isEmpty {
                        LabeledContent("Controller") { Text(controller).font(.caption) }
                    }

                    if let guide = programGuide {
                        Divider()
                        Text("Controller program guide").font(.subheadline.bold())
                        IrrigationProgramGuideView(guide: guide)
                    }

                    HStack {
                        NavigationLink {
                            IrrigationDetailView(
                                customerId: customerId,
                                propertyId: property.id,
                                propertyName: property.name ?? "Property"
                            )
                        } label: {
                            Label("View map", systemImage: "map")
                                .font(.subheadline)
                        }

                        NavigationLink {
                            IrrigationMapEditorView(
                                customerId: customerId,
                                propertyId: property.id,
                                propertyName: property.name ?? "Property"
                            )
                        } label: {
                            Label("Edit map", systemImage: "pencil")
                                .font(.subheadline)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let mapResponse: IrrigationMapResponse = try await env.apiClient.get(
                path: APIPath.irrigationMap(customerId: customerId, propertyId: property.id)
            )
            mapProperty = mapResponse.property
            let programResponse: IrrigationProgramResponse = try await env.apiClient.get(
                path: APIPath.irrigationProgram(customerId: customerId, propertyId: property.id)
            )
            programGuide = programResponse.guide
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
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
                        maxHeight: 420
                    )

                    if let zones = property.irrigationMapZones, !zones.isEmpty {
                        IrrigationZoneLegend(zones: zones)
                    }

                    if let diagram = property.propertyDiagramUrl, diagram != property.aerialImageUrl {
                        Text("Property diagram").font(.headline)
                        AuthenticatedBlobImage(urlString: diagram)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                if let guide = programGuide {
                    StormCard {
                        VStack(alignment: .leading, spacing: 8) {
                            StormSectionHeader(title: "Program guide", systemImage: "clock")
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
