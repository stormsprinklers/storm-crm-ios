import Foundation
import SwiftUI

@MainActor
final class IrrigationMapEditorViewModel: ObservableObject {
    @Published var zones: [EditableIrrigationZone] = []
    @Published var markers: [EditableMapMarker] = []
    @Published var waterSource = ""
    @Published var shutoffLocation = ""
    @Published var controllerLocation = ""
    @Published var mapStatus: String?
    @Published var imageUrl: String?
    @Published var programGuide: ControllerProgramGuideDTO?
    @Published var grassSeason = "COOL"
    @Published var droughtRestrictions = false
    @Published var cycleSoakEnabled = false
    @Published var etoOverride = ""
    @Published var activeZoneIndex = 0
    @Published var markerPlacement: String?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var isCapturingAerial = false
    @Published var error: String?
    @Published var successMessage: String?

    let customerId: String
    let propertyId: String
    let propertyName: String

    init(customerId: String, propertyId: String, propertyName: String) {
        self.customerId = customerId
        self.propertyId = propertyId
        self.propertyName = propertyName
    }

    var mapImageUrl: String? {
        imageUrl
    }

    func load(api: APIClient) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let mapResponse: IrrigationMapResponse = try await api.get(
                path: APIPath.irrigationMap(customerId: customerId, propertyId: propertyId)
            )
            applyProperty(mapResponse.property)

            let programResponse: IrrigationProgramResponse = try await api.get(
                path: APIPath.irrigationProgram(customerId: customerId, propertyId: propertyId)
            )
            programGuide = programResponse.guide
            if let settings = programResponse.settings {
                grassSeason = settings.grassSeason ?? "COOL"
                droughtRestrictions = settings.droughtRestrictionsActive ?? false
                cycleSoakEnabled = settings.cycleSoakEnabled ?? false
                if let override = settings.etoOverrideInches {
                    etoOverride = String(override)
                }
            }
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func captureAerial(api: APIClient) async {
        isCapturingAerial = true
        error = nil
        successMessage = nil
        defer { isCapturingAerial = false }
        do {
            let response: AerialCaptureResponse = try await api.post(
                path: APIPath.irrigationMapAerial(customerId: customerId, propertyId: propertyId)
            )
            imageUrl = response.aerialImageUrl
            // Reload so any zones the server remapped onto the new image come back aligned.
            await reloadMap(api: api)
            successMessage = "Aerial image captured"
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    /// Crop/zoom the aerial into the selected region. The server recaptures a sharper image and
    /// remaps existing zone/marker geometry to it, so we reload after the request completes.
    func cropAerial(api: APIClient, crop: AerialCropRect) async {
        isCapturingAerial = true
        error = nil
        successMessage = nil
        defer { isCapturingAerial = false }
        do {
            let _: AerialCaptureResponse = try await api.post(
                path: APIPath.irrigationMapAerial(customerId: customerId, propertyId: propertyId),
                body: AerialCropRequest(crop: crop)
            )
            await reloadMap(api: api)
            successMessage = "Zoomed in — zones realigned to the new image"
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func reloadMap(api: APIClient) async {
        do {
            let mapResponse: IrrigationMapResponse = try await api.get(
                path: APIPath.irrigationMap(customerId: customerId, propertyId: propertyId)
            )
            applyProperty(mapResponse.property)
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func save(api: APIClient, publish: Bool) async {
        isSaving = true
        error = nil
        successMessage = nil
        defer { isSaving = false }
        do {
            let body = buildPatchRequest(publish: publish)
            let response: IrrigationMapResponse = try await api.patch(
                path: APIPath.irrigationMap(customerId: customerId, propertyId: propertyId),
                body: body
            )
            applyProperty(response.property)
            successMessage = publish ? "Saved and published to portal" : "Map saved"

            let programResponse: IrrigationProgramResponse = try await api.get(
                path: APIPath.irrigationProgram(customerId: customerId, propertyId: propertyId)
            )
            programGuide = programResponse.guide
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func saveProgramSettings(api: APIClient) async {
        isSaving = true
        error = nil
        successMessage = nil
        defer { isSaving = false }
        do {
            let override = Double(etoOverride.trimmingCharacters(in: .whitespacesAndNewlines))
            let body = IrrigationProgramSettingsPatch(
                grassSeason: grassSeason,
                droughtRestrictionsActive: droughtRestrictions,
                cycleSoakEnabled: cycleSoakEnabled,
                etoOverrideInches: override
            )
            let response: IrrigationProgramResponse = try await api.post(
                path: APIPath.irrigationProgram(customerId: customerId, propertyId: propertyId),
                body: body
            )
            programGuide = response.guide

            // Saving settings should also publish the map to the customer portal.
            let mapBody = buildPatchRequest(publish: true)
            let mapResponse: IrrigationMapResponse = try await api.patch(
                path: APIPath.irrigationMap(customerId: customerId, propertyId: propertyId),
                body: mapBody
            )
            applyProperty(mapResponse.property)
            successMessage = "Settings saved and published to portal"
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func refreshProgramGuide(api: APIClient) async {
        do {
            let response: IrrigationProgramResponse = try await api.get(
                path: APIPath.irrigationProgram(customerId: customerId, propertyId: propertyId),
                query: [URLQueryItem(name: "refresh", value: "1")]
            )
            programGuide = response.guide
            successMessage = "Weather refreshed"
        } catch {
            self.error = (error as? APIError)?.message
        }
    }

    func addZone() {
        let index = zones.count + 1
        zones.append(EditableIrrigationZone.makeDefault(name: "Zone \(index)"))
        activeZoneIndex = zones.count - 1
    }

    func removeZone(at index: Int) {
        guard zones.count > 1, index >= 0, index < zones.count else { return }
        zones.remove(at: index)
        activeZoneIndex = min(activeZoneIndex, zones.count - 1)
    }

    func renameZone(at index: Int, name: String) {
        guard index >= 0, index < zones.count else { return }
        zones[index].name = name
    }

    func setPolygon(at index: Int, polygon: ImagePolygon?) {
        guard index >= 0, index < zones.count else { return }
        zones[index].polygon = polygon
    }

    func placeMarker(type: String, at point: ImagePoint) {
        let style = IrrigationConstants.markerStyle(for: type)
        let count = markers.filter { $0.type == type }.count
        let label = "\(style.label) \(count + 1)"
        markers.append(EditableMapMarker.new(type: type, label: label))
        if let idx = markers.indices.last {
            markers[idx].point = point
        }
        markerPlacement = nil
    }

    func removeMarker(id: String) {
        markers.removeAll { $0.id == id }
    }

    private func applyProperty(_ property: IrrigationMapProperty) {
        imageUrl = property.displayImageUrl
        mapStatus = property.irrigationMapStatus
        waterSource = property.waterSource ?? ""
        shutoffLocation = property.shutoffValveLocation ?? ""
        controllerLocation = property.controllerLocation ?? ""
        zones = property.editableZones()
        markers = property.editableMarkers()
        activeZoneIndex = min(activeZoneIndex, max(0, zones.count - 1))
    }

    private func buildPatchRequest(publish: Bool) -> IrrigationMapPatchRequest {
        let valves = markers
            .filter { $0.type == "VALVE" && $0.point != nil }
            .map {
                IrrigationPointPatch(
                    label: $0.label,
                    pointGeoJson: PolygonGeometry.pointToGeoJson($0.point),
                    zoneIds: []
                )
            }

        let controllers = markers
            .filter { $0.type == "TIMER" && $0.point != nil }
            .map {
                IrrigationControllerPatch(
                    label: $0.label,
                    pointGeoJson: PolygonGeometry.pointToGeoJson($0.point),
                    stationCount: 1
                )
            }

        let mapMarkers = markers
            .filter { ["POC", "FILTER", "BACKFLOW"].contains($0.type) && $0.point != nil }
            .map {
                IrrigationMarkerPatch(
                    type: $0.type,
                    label: $0.label,
                    pointGeoJson: PolygonGeometry.pointToGeoJson($0.point)
                )
            }

        let mapZones = zones.map { zone in
            let gpm = IrrigationConstants.resolveZoneGpm(
                irrigationType: zone.irrigationType,
                nozzleCount: zone.nozzleCount,
                estimatedGpm: zone.estimatedGpm,
                nozzleGpm: zone.nozzleGpm
            )
            return IrrigationMapZonePatch(
                name: zone.name,
                polygonGeoJson: PolygonGeometry.polygonToGeoJson(zone.polygon),
                vegetationType: zone.vegetationType,
                shadeLevel: zone.shadeLevel,
                slopeLevel: zone.slopeLevel,
                soilType: zone.soilType,
                irrigationType: zone.irrigationType,
                nozzleCount: zone.nozzleCount,
                estimatedGpm: gpm,
                irrigatedSqFt: zone.irrigatedSqFt,
                irrigationEfficiencyScore: zone.irrigationEfficiencyScore,
                establishmentStage: zone.establishmentStage,
                nozzleGpm: zone.nozzleGpm,
                baseRuntimeMinutes: zone.baseRuntimeMinutes
            )
        }

        return IrrigationMapPatchRequest(
            property: IrrigationPropertyPatch(
                waterSource: waterSource.isEmpty ? nil : waterSource,
                irrigationZoneCount: zones.count,
                shutoffValveLocation: shutoffLocation.isEmpty ? nil : shutoffLocation,
                controllerLocation: controllerLocation.isEmpty ? nil : controllerLocation
            ),
            mapZones: mapZones,
            valves: valves,
            controllers: controllers,
            mapMarkers: mapMarkers,
            publish: publish
        )
    }
}
