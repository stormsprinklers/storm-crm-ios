import SwiftUI

struct CustomerPropertiesSection: View {
    let customerId: String
    let properties: [CustomerPropertyDTO]

    var body: some View {
        if properties.isEmpty {
            StormCard {
                VStack(alignment: .leading, spacing: 8) {
                    StormSectionHeader(title: "Properties", systemImage: "house")
                    Text("No properties on file")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            ForEach(properties) { property in
                CustomerPropertyInlineSection(
                    customerId: customerId,
                    property: property
                )
            }
        }
    }
}

struct CustomerPropertyInlineSection: View {
    let customerId: String
    let property: CustomerPropertyDTO

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(property.name)
                                .font(.headline)
                            if property.isPrimary == true {
                                StormBadge(text: "Primary", style: .accent)
                            }
                        }
                        if !property.formattedAddress.isEmpty {
                            Text(property.formattedAddress)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if property.irrigationMapStatus == "PUBLISHED" {
                        StormBadge(text: "Map published", style: .success)
                    }
                }

                PropertyInfoSummaryRows(property: property)

                if !property.formattedAddress.isEmpty {
                    PropertyLocationEmbedsView(addressQuery: property.formattedAddress)
                }

                PropertyIrrigationInlineSection(
                    customerId: customerId,
                    propertyId: property.id,
                    propertyName: property.name,
                    fallbackAerialUrl: nil,
                    showsEditLink: true
                )

                RachioPropertySection(
                    customerId: customerId,
                    propertyId: property.id,
                    embedded: true
                )
            }
        }
    }
}

struct PropertyInfoSummaryRows: View {
    let property: CustomerPropertyDTO

    private var hasInfo: Bool {
        property.irrigationZoneCount != nil
            || !(property.shutoffValveLocation ?? "").isEmpty
            || !(property.controllerLocation ?? "").isEmpty
            || property.irrigationMapStatus != nil
    }

    var body: some View {
        if hasInfo {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Property info", systemImage: "info.circle")
                if let zones = property.irrigationZoneCount, zones > 0 {
                    LabeledContent("Irrigation zones") {
                        Text("\(zones)")
                            .font(.subheadline.weight(.medium))
                    }
                }
                if let shutoff = property.shutoffValveLocation, !shutoff.isEmpty {
                    LabeledContent("Shutoff") {
                        Text(shutoff)
                            .font(.subheadline)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let controller = property.controllerLocation, !controller.isEmpty {
                    LabeledContent("Controller") {
                        Text(controller)
                            .font(.subheadline)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let status = property.irrigationMapStatus, !status.isEmpty {
                    LabeledContent("Map status") {
                        Text(status.replacingOccurrences(of: "_", with: " "))
                            .font(.subheadline)
                    }
                }
            }
        }
    }
}

struct PropertyLocationEmbedsView: View {
    @EnvironmentObject private var env: AppEnvironment
    let addressQuery: String

    @State private var embeds: MapsEmbedResponse?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StormSectionHeader(title: "Location", systemImage: "map")

            if isLoading {
                ProgressView("Loading street view…")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                if let streetEmbed = embeds?.streetEmbed, let url = URL(string: streetEmbed) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Street view")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        GoogleMapsEmbedWebView(url: url)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                if let placeEmbed = embeds?.placeEmbed, let url = URL(string: placeEmbed) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Map")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        GoogleMapsEmbedWebView(url: url)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                if embeds?.configured == false {
                    Text("Set GOOGLE_MAPS_API_KEY on the CRM server to show street view and map embeds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if embeds?.streetEmbed == nil, embeds?.placeEmbed == nil {
                    Text("Map preview is not available for this address.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let formatted = embeds?.formattedAddress, !formatted.isEmpty {
                    Text(formatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let url = mapsDirectionsURL {
                    Link(destination: url) {
                        Label("Open in Maps", systemImage: "arrow.triangle.turn.up.right.diamond")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(StormTheme.sky)
                }
            }
        }
        .task(id: addressQuery) { await load() }
    }

    private var mapsDirectionsURL: URL? {
        AppleMapsURL.directionsURL(latitude: nil, longitude: nil, address: addressQuery)
    }

    private func load() async {
        guard !addressQuery.isEmpty else { return }
        isLoading = embeds == nil
        error = nil
        defer { isLoading = false }
        do {
            embeds = try await env.apiClient.get(
                path: APIPath.mapsEmbed,
                query: [URLQueryItem(name: "q", value: addressQuery)]
            )
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

