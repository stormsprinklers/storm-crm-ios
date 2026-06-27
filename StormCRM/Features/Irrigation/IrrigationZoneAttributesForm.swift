import SwiftUI

struct IrrigationZoneAttributesForm: View {
    @Binding var zone: EditableIrrigationZone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(zone.name) — zone attributes")
                .font(.subheadline.bold())

            pickerRow("Vegetation", selection: $zone.vegetationType, options: IrrigationConstants.vegetationTypes)

            HStack(spacing: 8) {
                pickerColumn("Shade", selection: $zone.shadeLevel, options: IrrigationConstants.shadeLevels)
                pickerColumn("Slope", selection: $zone.slopeLevel, options: IrrigationConstants.slopeLevels)
                pickerColumn("Soil", selection: $zone.soilType, options: IrrigationConstants.soilTypes)
            }

            pickerRow("Irrigation type", selection: $zone.irrigationType, options: IrrigationConstants.irrigationTypes)

            HStack(spacing: 12) {
                numberField("Nozzles", value: Binding(
                    get: { String(zone.nozzleCount) },
                    set: { zone.nozzleCount = Int($0) ?? zone.nozzleCount }
                ))
                numberField("Nozzle GPM", value: Binding(
                    get: { zone.nozzleGpm.map { String($0) } ?? "" },
                    set: { zone.nozzleGpm = Double($0) }
                ))
                numberField("Total GPM", value: Binding(
                    get: { zone.estimatedGpm.map { String($0) } ?? "" },
                    set: { zone.estimatedGpm = Double($0) }
                ))
            }

            HStack(spacing: 12) {
                numberField("Sq ft", value: Binding(
                    get: { zone.irrigatedSqFt.map { String($0) } ?? "" },
                    set: { zone.irrigatedSqFt = Int($0) }
                ))
                numberField("Efficiency", value: Binding(
                    get: { zone.irrigationEfficiencyScore.map { String($0) } ?? "" },
                    set: { zone.irrigationEfficiencyScore = Int($0) }
                ))
                numberField("Base min", value: Binding(
                    get: { zone.baseRuntimeMinutes.map { String($0) } ?? "" },
                    set: { zone.baseRuntimeMinutes = Double($0) }
                ))
            }

            pickerRow("Establishment", selection: $zone.establishmentStage, options: IrrigationConstants.establishmentStages)

            let computedGpm = IrrigationConstants.resolveZoneGpm(
                irrigationType: zone.irrigationType,
                nozzleCount: zone.nozzleCount,
                estimatedGpm: zone.estimatedGpm,
                nozzleGpm: zone.nozzleGpm
            )
            Text("Computed GPM: \(computedGpm, format: .number.precision(.fractionLength(2)))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(StormTheme.ice.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func pickerRow(
        _ title: String,
        selection: Binding<String>,
        options: [IrrigationConstants.LabeledOption]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func pickerColumn(
        _ title: String,
        selection: Binding<String>,
        options: [IrrigationConstants.LabeledOption]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numberField(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField(title, text: value)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct IrrigationProgramSettingsForm: View {
    @Binding var grassSeason: String
    @Binding var droughtRestrictions: Bool
    @Binding var cycleSoakEnabled: Bool
    @Binding var etoOverride: String
    var onSave: () -> Void
    var onRefreshWeather: () -> Void
    var isSaving: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Program settings").font(.subheadline.bold())

            Picker("Grass season", selection: $grassSeason) {
                ForEach(IrrigationConstants.grassSeasons) { option in
                    Text(option.label).tag(option.value)
                }
            }

            Toggle("Drought restrictions", isOn: $droughtRestrictions)
            Toggle("Cycle & soak", isOn: $cycleSoakEnabled)

            HStack {
                TextField("ETo override (in/wk)", text: $etoOverride)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button(isSaving ? "Saving…" : "Save settings") { onSave() }
                    .buttonStyle(StormPrimaryButtonStyle())
                    .disabled(isSaving)
                Button("Refresh weather") { onRefreshWeather() }
                    .buttonStyle(StormSecondaryButtonStyle())
            }
        }
        .padding(12)
        .background(StormTheme.ice.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
