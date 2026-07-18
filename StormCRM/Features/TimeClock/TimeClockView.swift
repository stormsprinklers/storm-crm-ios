import SwiftUI

struct TimeClockView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var clock = TimeClockViewModel()
    @State private var timesheetEntries: [TimesheetEntryDTO] = []
    @State private var timesheetError: String?
    @State private var isLoadingTimesheets = false

    var body: some View {
        List {
            Section("Shift clock") {
                if let error = clock.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                if let open = clock.response?.openEntry {
                    LabeledContent("Clocked in", value: APIDateFormatting.displayString(from: open.clockInAt))
                    Button("Clock out", role: .destructive) {
                        Task { await clock.toggle(api: env.apiClient) }
                    }
                } else {
                    Button("Clock in") {
                        Task { await clock.toggle(api: env.apiClient) }
                    }
                    .buttonStyle(StormPrimaryButtonStyle())
                }

                if let hours = clock.response?.todayHours {
                    LabeledContent("Today", value: String(format: "%.2f hrs", hours))
                }
            }

            Section("Recent entries") {
                if isLoadingTimesheets && timesheetEntries.isEmpty {
                    ProgressView()
                } else if let timesheetError {
                    Text(timesheetError).font(.caption).foregroundStyle(.red)
                } else if timesheetEntries.isEmpty {
                    Text("No timesheet entries for this week.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(timesheetEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(APIDateFormatting.displayString(from: entry.clockInAt))
                                .font(.subheadline.weight(.medium))
                            if let clockOut = entry.clockOutAt {
                                Text("Out: \(APIDateFormatting.displayString(from: clockOut))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Still open")
                                    .font(.caption)
                                    .foregroundStyle(StormTheme.coral)
                            }
                            if let hours = entry.durationHours {
                                Text(String(format: "%.2f hours", hours))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Timesheets")
        .task {
            await clock.load(api: env.apiClient)
            await loadTimesheets()
        }
        .refreshable {
            await clock.load(api: env.apiClient)
            await loadTimesheets()
        }
    }

    private func loadTimesheets() async {
        isLoadingTimesheets = true
        timesheetError = nil
        defer { isLoadingTimesheets = false }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let endDay = calendar.date(byAdding: .day, value: 6, to: start),
              let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDay)
        else { return }

        do {
            let response: TimesheetsResponse = try await env.apiClient.get(
                path: APIPath.timesheets,
                query: [
                    URLQueryItem(name: "from", value: APIDateFormatting.queryString(from: start)),
                    URLQueryItem(name: "to", value: APIDateFormatting.queryString(from: end)),
                ]
            )
            timesheetEntries = response.entries
        } catch {
            timesheetError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct TimesheetsResponse: Decodable {
    let entries: [TimesheetEntryDTO]
}

struct TimesheetEntryDTO: Decodable, Identifiable {
    let id: String
    let clockInAt: String
    let clockOutAt: String?
    let durationHours: Double?
}
