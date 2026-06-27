import SwiftUI

struct IrrigationProgramGuideView: View {
    let guide: ControllerProgramGuideDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let generatedAt = guide.generatedAt {
                Text("Generated \(APIDateFormatting.displayString(from: generatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                weatherStat("ETo", guide.weeklyEToInches, suffix: " in/wk")
                weatherStat("Rain", guide.totalRainfallInches, suffix: " in")
                if guide.droughtMode == true {
                    StormBadge(text: "Drought mode", style: .warning)
                }
                if guide.cycleSoakEnabled == true {
                    StormBadge(text: "Cycle & soak")
                }
            }

            if let programs = guide.programs, !programs.isEmpty {
                ForEach(programs) { program in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Program \(program.label)")
                                .font(.subheadline.bold())
                            if let days = program.daysLabel {
                                Text(days).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let starts = program.startTimes, !starts.isEmpty {
                            Text("Start: \(starts.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let zones = program.zones {
                            ForEach(zones) { zone in
                                HStack {
                                    Text("St \(zone.stationNumber.map(String.init) ?? "—") · \(zone.name)")
                                        .font(.caption)
                                    Spacer()
                                    if let mins = zone.runtimePerEventMinutes {
                                        Text("\(Int(mins)) min/event")
                                            .font(.caption.monospacedDigit())
                                    }
                                }
                            }
                        }
                        if let wall = program.totalWallClockMinutes {
                            Text("Wall clock: \(Int(wall)) min")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(StormTheme.ice.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            if let notes = guide.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes").font(.caption.bold())
                    ForEach(notes, id: \.self) { note in
                        Text("• \(note)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if let gallons = guide.totalGallonsPerWeek {
                Text("Total: \(Int(gallons)) gal/week")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(StormTheme.navy)
            }
        }
    }

    private func weatherStat(_ label: String, _ value: Double?, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            if let value {
                Text(String(format: "%.2f%@", value, suffix))
                    .font(.caption.weight(.semibold))
            } else {
                Text("—").font(.caption)
            }
        }
    }
}
