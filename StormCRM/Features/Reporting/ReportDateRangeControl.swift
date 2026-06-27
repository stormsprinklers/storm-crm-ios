import SwiftUI

struct ReportDateRangeControl: View {
    @Binding var range: ReportDateRange

    @State private var showEditor = false

    var body: some View {
        Button {
            showEditor = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                Text(range.displayLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(StormTheme.navy)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.separator), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showEditor) {
            ReportDateRangeEditor(range: $range)
        }
    }
}

private struct ReportDateRangeEditor: View {
    @Binding var range: ReportDateRange
    @Environment(\.dismiss) private var dismiss

    @State private var draftStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var draftEnd = Date()
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Presets") {
                    ForEach(ReportDateRangePreset.allCases) { preset in
                        Button {
                            range = ReportDateRange(selection: .preset(preset))
                            dismiss()
                        } label: {
                            HStack {
                                Text(preset.label)
                                Spacer()
                                if case .preset(let selected) = range.selection, selected == preset {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(StormTheme.sky)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section("Custom range") {
                    DatePicker("From", selection: $draftStart, displayedComponents: .date)
                    DatePicker("To", selection: $draftEnd, displayedComponents: .date)

                    if let validationError {
                        Text(validationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Apply custom range") {
                        applyCustomRange()
                    }
                }
            }
            .navigationTitle("Date range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if case .custom(let start, let end) = range.selection {
                    draftStart = start
                    draftEnd = end
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func applyCustomRange() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: draftStart)
        let end = calendar.startOfDay(for: draftEnd)
        guard start <= end else {
            validationError = "Start date must be on or before end date."
            return
        }
        validationError = nil
        range = ReportDateRange(selection: .custom(start: start, end: end))
        dismiss()
    }
}
