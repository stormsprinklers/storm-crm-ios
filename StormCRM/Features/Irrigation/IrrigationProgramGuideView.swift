import SwiftUI

/// Matches web `SprinklerProgrammingSetupTable` mobile card layout.
struct IrrigationProgramGuideView: View {
    let guide: ControllerProgramGuideDTO

    private var programs: [ControllerProgramDTO] {
        (guide.programs ?? []).filter { !($0.zones ?? []).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sprinkler Programming Setup")
                    .font(.headline)
                Text("Each runtime occurs on every watering day for each start time listed in that program.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if programs.isEmpty {
                Text("Add zones with vegetation and irrigation types to generate a programming guide.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(programs) { program in
                    ProgramSetupCard(program: program)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(footerSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let notes = guide.notes, !notes.isEmpty {
                        ForEach(notes, id: \.self) { note in
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerSummary: String {
        let gal = Int((guide.totalGallonsPerWeek ?? 0).rounded())
        let eto = guide.weeklyEToInches.map { String(format: "%.2f", $0) } ?? "—"
        var parts = ["~\(gal.formatted()) gal/week total", "ET₀ \(eto)\"/wk"]
        if guide.droughtMode == true {
            parts.append("Drought schedule")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ProgramSetupCard: View {
    let program: ControllerProgramDTO

    private var tint: Color {
        switch program.id.uppercased() {
        case "B": return Color.green.opacity(0.08)
        case "C": return Color.orange.opacity(0.10)
        default: return Color(.secondarySystemGroupedBackground)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Program \(program.id)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    if let days = program.daysLabel, !days.isEmpty {
                        Text(days)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                if let starts = program.startTimes, !starts.isEmpty {
                    Text("Start Times: \(starts.joined(separator: " · "))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if program.isEstablishment == true {
                    Text("Establishment (temporary)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.orange.opacity(0.95))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.12, green: 0.16, blue: 0.22))

            let zones = program.zones ?? []
            VStack(spacing: 0) {
                ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                    ZoneSetupRow(zone: zone)
                    if index < zones.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(tint)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ZoneSetupRow: View {
    let zone: ProgramZoneRuntimeDTO

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(zoneTitle)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                if let note = zone.establishmentNote, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(runtimeLabel)
                    .font(.subheadline.monospacedDigit())
                Text(gallonsLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var zoneTitle: String {
        let station = zone.stationNumber.map { "#\($0)" } ?? "#"
        return "\(station) \(zone.name)"
    }

    private var runtimeLabel: String {
        // Do not append ×2/×3 for multiple starts — Start Times already lists each one.
        if let minutes = zone.runtimePerEventMinutes {
            return "\(Int(minutes.rounded())) min"
        }
        if let cs = zone.cycleSoak,
           cs.enabled == true,
           let perCycle = cs.minutesPerCycle {
            let cycles = max(cs.cycleCount ?? 1, 1)
            return "\(Int((perCycle * Double(cycles)).rounded())) min"
        }
        return "0 min"
    }

    private var gallonsLabel: String {
        let gal = Int((zone.gallonsPerEvent ?? 0).rounded())
        return "\(gal.formatted()) gal"
    }
}
