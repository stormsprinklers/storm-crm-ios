import SwiftUI

/// Matches web `SprinklerProgrammingSetupTable` mobile card layout.
struct IrrigationProgramGuideView: View {
    let guide: ControllerProgramGuideDTO

    private var programs: [ControllerProgramDTO] {
        (guide.programs ?? []).filter { !($0.zones ?? []).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title comes from the parent section (e.g. "Controller program guide").
            Text("Program each zone for the minutes shown at every start time. Total is all starts combined on a watering day.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
                    HStack(alignment: .top, spacing: 6) {
                        Text("Start Times")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.black.opacity(0.85))
                        Text(starts.joined(separator: " · "))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.black.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                    ZoneSetupRow(zone: zone, startTimes: program.startTimes ?? [])
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
    let startTimes: [String]

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

            VStack(alignment: .trailing, spacing: 3) {
                ForEach(startBreakdowns, id: \.time) { start in
                    Text("\(start.time)  \(start.minutes) min")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(start.minutes > 0 ? .primary : .secondary)
                }
                Text("Total \(totalMinutes) min")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
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

    private var cycleCount: Int {
        if zone.cycleSoak?.enabled == true {
            return max(zone.cycleSoak?.cycleCount ?? 1, 1)
        }
        return 1
    }

    private var minutesPerStart: Int {
        if zone.cycleSoak?.enabled == true, let perCycle = zone.cycleSoak?.minutesPerCycle {
            return Int(perCycle.rounded())
        }
        return Int((zone.runtimePerEventMinutes ?? 0).rounded())
    }

    private var startBreakdowns: [(time: String, minutes: Int)] {
        let times = startTimes.isEmpty ? ["Start"] : startTimes
        return times.enumerated().map { index, time in
            (time: time, minutes: index < cycleCount ? minutesPerStart : 0)
        }
    }

    private var totalMinutes: Int {
        if let total = zone.runtimePerEventMinutes {
            return Int(total.rounded())
        }
        return startBreakdowns.reduce(0) { $0 + $1.minutes }
    }

    private var gallonsLabel: String {
        let gal = Int((zone.gallonsPerEvent ?? 0).rounded())
        return "\(gal.formatted()) gal / watering day"
    }
}
