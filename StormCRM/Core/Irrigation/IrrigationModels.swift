import Foundation

struct IrrigationMapResponse: Decodable {
    let property: IrrigationMapProperty
}

struct IrrigationMapProperty: Decodable {
    let id: String
    let name: String?
    let aerialImageUrl: String?
    let propertyDiagramUrl: String?
    let irrigationMapStatus: String?
    let shutoffValveLocation: String?
    let controllerLocation: String?
    let waterSource: String?
    let irrigationZoneCount: Int?
    let grassSeason: String?
    let droughtRestrictionsActive: Bool?
    let cycleSoakEnabled: Bool?
    let etoOverrideInches: Double?
    let irrigationMapZones: [IrrigationMapZoneDTO]?
    let irrigationMapMarkers: [IrrigationMapMarkerDTO]?
    let irrigationValves: [IrrigationValveDTO]?
    let irrigationControllers: [IrrigationControllerDTO]?

    var displayImageUrl: String? {
        propertyDiagramUrl ?? aerialImageUrl
    }
}

struct IrrigationMapZoneDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let sortOrder: Int?
    let polygonGeoJson: JSONValue?
    let vegetationType: String?
    let shadeLevel: String?
    let slopeLevel: String?
    let soilType: String?
    let irrigationType: String?
    let nozzleCount: Int?
    let estimatedGpm: Double?
    let nozzleGpm: Double?
    let baseRuntimeMinutes: Double?
    let irrigatedSqFt: Int?
    let irrigationEfficiencyScore: Int?
    let establishmentStage: String?

    enum CodingKeys: String, CodingKey {
        case id, name, sortOrder, polygonGeoJson, vegetationType, shadeLevel, slopeLevel
        case soilType, irrigationType, nozzleCount, estimatedGpm, nozzleGpm
        case baseRuntimeMinutes, irrigatedSqFt, irrigationEfficiencyScore, establishmentStage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
        polygonGeoJson = try container.decodeIfPresent(JSONValue.self, forKey: .polygonGeoJson)
        vegetationType = try container.decodeIfPresent(String.self, forKey: .vegetationType)
        shadeLevel = try container.decodeIfPresent(String.self, forKey: .shadeLevel)
        slopeLevel = try container.decodeIfPresent(String.self, forKey: .slopeLevel)
        soilType = try container.decodeIfPresent(String.self, forKey: .soilType)
        irrigationType = try container.decodeIfPresent(String.self, forKey: .irrigationType)
        nozzleCount = try container.decodeIfPresent(Int.self, forKey: .nozzleCount)
        estimatedGpm = try container.decodeFlexibleDouble(forKey: .estimatedGpm)
        nozzleGpm = try container.decodeFlexibleDouble(forKey: .nozzleGpm)
        baseRuntimeMinutes = try container.decodeFlexibleDouble(forKey: .baseRuntimeMinutes)
        irrigatedSqFt = try container.decodeIfPresent(Int.self, forKey: .irrigatedSqFt)
        irrigationEfficiencyScore = try container.decodeIfPresent(Int.self, forKey: .irrigationEfficiencyScore)
        establishmentStage = try container.decodeIfPresent(String.self, forKey: .establishmentStage)
    }

    var polygon: ImagePolygon? {
        PolygonGeometry.polygon(from: polygonGeoJson)
    }
}

struct IrrigationMapMarkerDTO: Decodable, Identifiable {
    let id: String
    let type: String
    let label: String?
    let pointGeoJson: JSONValue?

    enum CodingKeys: String, CodingKey {
        case id, type, label, pointGeoJson, kind, locationGeoJson
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decodeIfPresent(String.self, forKey: .type)
            ?? container.decodeIfPresent(String.self, forKey: .kind)
            ?? "POC"
        label = try container.decodeIfPresent(String.self, forKey: .label)
        pointGeoJson = try container.decodeIfPresent(JSONValue.self, forKey: .pointGeoJson)
            ?? container.decodeIfPresent(JSONValue.self, forKey: .locationGeoJson)
    }

    init(id: String, type: String, label: String?, point: ImagePoint) {
        self.id = id
        self.type = type
        self.label = label
        self.pointGeoJson = PolygonGeometry.pointToGeoJson(point)
    }

    var point: ImagePoint? {
        PolygonGeometry.point(from: pointGeoJson)
    }
}

struct IrrigationValveDTO: Decodable, Identifiable {
    let id: String
    let label: String
    let pointGeoJson: JSONValue?

    var point: ImagePoint? {
        PolygonGeometry.point(from: pointGeoJson)
    }
}

struct IrrigationControllerDTO: Decodable, Identifiable {
    let id: String
    let label: String
    let pointGeoJson: JSONValue?

    var point: ImagePoint? {
        PolygonGeometry.point(from: pointGeoJson)
    }
}

struct EditableIrrigationZone: Identifiable, Equatable {
    var id: String
    var name: String
    var polygon: ImagePolygon?
    var vegetationType: String
    var shadeLevel: String
    var slopeLevel: String
    var soilType: String
    var irrigationType: String
    var nozzleCount: Int
    var estimatedGpm: Double?
    var baseRuntimeMinutes: Double?
    var irrigatedSqFt: Int?
    var irrigationEfficiencyScore: Int?
    var establishmentStage: String
    var nozzleGpm: Double?

    static func makeDefault(name: String) -> EditableIrrigationZone {
        EditableIrrigationZone(
            id: UUID().uuidString,
            name: name,
            polygon: nil,
            vegetationType: "grass",
            shadeLevel: "full_sun",
            slopeLevel: "flat",
            soilType: "loam",
            irrigationType: "spray",
            nozzleCount: 4,
            estimatedGpm: nil,
            baseRuntimeMinutes: nil,
            irrigatedSqFt: nil,
            irrigationEfficiencyScore: nil,
            establishmentStage: "NORMAL",
            nozzleGpm: nil
        )
    }

    static func from(dto: IrrigationMapZoneDTO) -> EditableIrrigationZone {
        EditableIrrigationZone(
            id: dto.id,
            name: dto.name,
            polygon: dto.polygon,
            vegetationType: dto.vegetationType ?? "grass",
            shadeLevel: dto.shadeLevel ?? "full_sun",
            slopeLevel: dto.slopeLevel ?? "flat",
            soilType: dto.soilType ?? "loam",
            irrigationType: dto.irrigationType ?? "spray",
            nozzleCount: dto.nozzleCount ?? 4,
            estimatedGpm: dto.estimatedGpm,
            baseRuntimeMinutes: dto.baseRuntimeMinutes,
            irrigatedSqFt: dto.irrigatedSqFt,
            irrigationEfficiencyScore: dto.irrigationEfficiencyScore,
            establishmentStage: dto.establishmentStage ?? "NORMAL",
            nozzleGpm: dto.nozzleGpm
        )
    }
}

struct EditableMapMarker: Identifiable, Equatable {
    var id: String
    var type: String
    var label: String
    var point: ImagePoint?

    static func new(type: String, label: String) -> EditableMapMarker {
        EditableMapMarker(id: UUID().uuidString, type: type, label: label, point: nil)
    }
}

struct IrrigationProgramResponse: Decodable {
    let guide: ControllerProgramGuideDTO
    let settings: IrrigationSettingsDTO?
    let weather: IrrigationWeatherDTO?
    let zoneCount: Int?
}

struct IrrigationSettingsDTO: Decodable {
    let grassSeason: String?
    let droughtRestrictionsActive: Bool?
    let cycleSoakEnabled: Bool?
    let etoOverrideInches: Double?

    enum CodingKeys: String, CodingKey {
        case grassSeason, droughtRestrictionsActive, cycleSoakEnabled, etoOverrideInches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        grassSeason = try container.decodeIfPresent(String.self, forKey: .grassSeason)
        droughtRestrictionsActive = try container.decodeIfPresent(Bool.self, forKey: .droughtRestrictionsActive)
        cycleSoakEnabled = try container.decodeIfPresent(Bool.self, forKey: .cycleSoakEnabled)
        etoOverrideInches = try container.decodeFlexibleDouble(forKey: .etoOverrideInches)
    }
}

struct IrrigationWeatherDTO: Decodable {
    let weeklyEToInches: Double?
    let totalRainfallInches: Double?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case weeklyEToInches, totalRainfallInches, source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weeklyEToInches = try container.decodeFlexibleDouble(forKey: .weeklyEToInches)
        totalRainfallInches = try container.decodeFlexibleDouble(forKey: .totalRainfallInches)
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }
}

struct ControllerProgramGuideDTO: Decodable {
    let generatedAt: String?
    let weeklyEToInches: Double?
    let totalRainfallInches: Double?
    let effectiveRainInches: Double?
    let droughtMode: Bool?
    let cycleSoakEnabled: Bool?
    let grassSeason: String?
    let weatherSource: String?
    let programs: [ControllerProgramDTO]?
    let totalGallonsPerWeek: Double?
    let notes: [String]?

    enum CodingKeys: String, CodingKey {
        case generatedAt, weeklyEToInches, totalRainfallInches, effectiveRainInches
        case droughtMode, cycleSoakEnabled, grassSeason, weatherSource, programs
        case totalGallonsPerWeek, notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        weeklyEToInches = try container.decodeFlexibleDouble(forKey: .weeklyEToInches)
        totalRainfallInches = try container.decodeFlexibleDouble(forKey: .totalRainfallInches)
        effectiveRainInches = try container.decodeFlexibleDouble(forKey: .effectiveRainInches)
        droughtMode = try container.decodeIfPresent(Bool.self, forKey: .droughtMode)
        cycleSoakEnabled = try container.decodeIfPresent(Bool.self, forKey: .cycleSoakEnabled)
        grassSeason = try container.decodeIfPresent(String.self, forKey: .grassSeason)
        weatherSource = try container.decodeIfPresent(String.self, forKey: .weatherSource)
        programs = try container.decodeIfPresent([ControllerProgramDTO].self, forKey: .programs)
        totalGallonsPerWeek = try container.decodeFlexibleDouble(forKey: .totalGallonsPerWeek)
        notes = try container.decodeIfPresent([String].self, forKey: .notes)
    }
}

struct ControllerProgramDTO: Decodable, Identifiable {
    let id: String
    let label: String
    let daysLabel: String?
    let startTimes: [String]?
    let totalWallClockMinutes: Double?
    let zones: [ProgramZoneRuntimeDTO]?

    enum CodingKeys: String, CodingKey {
        case id, label, daysLabel, startTimes, totalWallClockMinutes, zones
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? label
        daysLabel = try container.decodeIfPresent(String.self, forKey: .daysLabel)
        startTimes = try container.decodeIfPresent([String].self, forKey: .startTimes)
        totalWallClockMinutes = try container.decodeFlexibleDouble(forKey: .totalWallClockMinutes)
        zones = try container.decodeIfPresent([ProgramZoneRuntimeDTO].self, forKey: .zones)
    }
}

struct ProgramZoneRuntimeDTO: Decodable, Identifiable {
    var id: String { zoneId ?? name }
    let zoneId: String?
    let name: String
    let stationNumber: Int?
    let runtimePerEventMinutes: Double?
    let daysPerWeek: Int?
    let weeklyRuntimeMinutes: Double?
    let startTime: String?
    let finishTime: String?

    enum CodingKeys: String, CodingKey {
        case zoneId, name, stationNumber, runtimePerEventMinutes, daysPerWeek
        case weeklyRuntimeMinutes, startTime, finishTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zoneId = try container.decodeIfPresent(String.self, forKey: .zoneId)
        name = try container.decode(String.self, forKey: .name)
        stationNumber = try container.decodeIfPresent(Int.self, forKey: .stationNumber)
        runtimePerEventMinutes = try container.decodeFlexibleDouble(forKey: .runtimePerEventMinutes)
        daysPerWeek = try container.decodeIfPresent(Int.self, forKey: .daysPerWeek)
        weeklyRuntimeMinutes = try container.decodeFlexibleDouble(forKey: .weeklyRuntimeMinutes)
        startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
        finishTime = try container.decodeIfPresent(String.self, forKey: .finishTime)
    }
}

struct AerialCaptureResponse: Decodable {
    let aerialImageUrl: String?
    let latitude: Double?
    let longitude: Double?
    let formattedAddress: String?
}

/// Normalized crop rectangle (each value 0..1) relative to the current aerial image.
struct AerialCropRect: Encodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct AerialCropRequest: Encodable {
    let crop: AerialCropRect
}

// MARK: - PATCH payloads

struct IrrigationMapPatchRequest: Encodable {
    let property: IrrigationPropertyPatch?
    let mapZones: [IrrigationMapZonePatch]?
    let valves: [IrrigationPointPatch]?
    let controllers: [IrrigationControllerPatch]?
    let mapMarkers: [IrrigationMarkerPatch]?
    let publish: Bool
}

struct IrrigationPropertyPatch: Encodable {
    let waterSource: String?
    let irrigationZoneCount: Int?
    let shutoffValveLocation: String?
    let controllerLocation: String?
}

struct IrrigationMapZonePatch: Encodable {
    let name: String
    let polygonGeoJson: JSONValue
    let vegetationType: String?
    let shadeLevel: String?
    let slopeLevel: String?
    let soilType: String?
    let irrigationType: String?
    let nozzleCount: Int?
    let estimatedGpm: Double?
    let irrigatedSqFt: Int?
    let irrigationEfficiencyScore: Int?
    let establishmentStage: String?
    let nozzleGpm: Double?
    let baseRuntimeMinutes: Double?
}

struct IrrigationPointPatch: Encodable {
    let label: String
    let pointGeoJson: JSONValue
    let zoneIds: [String]
}

struct IrrigationControllerPatch: Encodable {
    let label: String
    let pointGeoJson: JSONValue
    let stationCount: Int
}

struct IrrigationMarkerPatch: Encodable {
    let type: String
    let label: String?
    let pointGeoJson: JSONValue
}

struct IrrigationProgramSettingsPatch: Encodable {
    let grassSeason: String?
    let droughtRestrictionsActive: Bool?
    let cycleSoakEnabled: Bool?
    let etoOverrideInches: Double?
}

extension IrrigationMapProperty {
    func editableZones() -> [EditableIrrigationZone] {
        let list = irrigationMapZones ?? []
        if list.isEmpty {
            return [EditableIrrigationZone.makeDefault(name: "Zone 1")]
        }
        return list.map { EditableIrrigationZone.from(dto: $0) }
    }

    func editableMarkers() -> [EditableMapMarker] {
        var markers: [EditableMapMarker] = []
        for valve in irrigationValves ?? [] {
            guard let point = valve.point else { continue }
            markers.append(EditableMapMarker(id: valve.id, type: "VALVE", label: valve.label, point: point))
        }
        for controller in irrigationControllers ?? [] {
            guard let point = controller.point else { continue }
            markers.append(EditableMapMarker(id: controller.id, type: "TIMER", label: controller.label, point: point))
        }
        for marker in irrigationMapMarkers ?? [] {
            guard let point = marker.point else { continue }
            let style = IrrigationConstants.markerStyle(for: marker.type)
            markers.append(
                EditableMapMarker(
                    id: marker.id,
                    type: marker.type,
                    label: marker.label ?? style.label,
                    point: point
                )
            )
        }
        return markers
    }

    func allMarkersForDisplay() -> [IrrigationMapMarkerDTO] {
        editableMarkers().compactMap { marker in
            guard let point = marker.point else { return nil }
            return IrrigationMapMarkerDTO(id: marker.id, type: marker.type, label: marker.label, point: point)
        }
    }
}
