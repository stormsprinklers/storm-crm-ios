import SwiftUI

struct TimeOffRequestSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var startDate = Calendar.current.startOfDay(for: Date())
    @State private var endDate = Calendar.current.startOfDay(for: Date())
    @State private var type: TimeOffRequestType = .timeOff
    @State private var allDay = true
    @State private var reason = ""
    @State private var recent: [TimeOffRequestDTO] = []
    @State private var isSaving = false
    @State private var isLoadingRecent = false
    @State private var error: String?
    @State private var successMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Dates") {
                    DatePicker("Start", selection: $startDate, displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                    DatePicker("End", selection: $endDate, displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                    Toggle("All day", isOn: $allDay)
                }

                Section("Details") {
                    Picker("Type", selection: $type) {
                        ForEach(TimeOffRequestType.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    TextField("Reason (optional)", text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let successMessage {
                    Section {
                        Text(successMessage)
                            .font(.subheadline)
                            .foregroundStyle(StormTheme.success)
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Your recent requests") {
                    if isLoadingRecent && recent.isEmpty {
                        ProgressView()
                    } else if recent.isEmpty {
                        Text("No recent requests.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recent.prefix(8)) { request in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(TimeOffRequestType(rawValue: request.type)?.title ?? request.type)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(request.status.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(statusColor(request.status))
                                }
                                Text(dateRangeLabel(request))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let reason = request.reason, !reason.isEmpty {
                                    Text(reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Request time off")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { Task { await submit() } }
                        .disabled(isSaving)
                }
            }
            .task { await loadRecent() }
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "APPROVED": return StormTheme.success
        case "DENIED", "CANCELLED": return .red
        default: return .orange
        }
    }

    private func dateRangeLabel(_ request: TimeOffRequestDTO) -> String {
        let start = APIDateFormatting.displayString(from: request.startAt)
        let end = APIDateFormatting.displayString(from: request.endAt)
        return "\(start) – \(end)"
    }

    private func loadRecent() async {
        isLoadingRecent = true
        defer { isLoadingRecent = false }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        let end = calendar.date(byAdding: .month, value: 6, to: Date()) ?? Date()
        do {
            let response: TimeOffListResponse = try await env.apiClient.get(
                path: APIPath.scheduleTimeOff,
                query: [
                    URLQueryItem(name: "start", value: APIDateFormatting.queryString(from: start)),
                    URLQueryItem(name: "end", value: APIDateFormatting.queryString(from: end)),
                ]
            )
            recent = response.requests.sorted {
                (APIDateFormatting.parse($0.createdAt) ?? .distantPast) >
                    (APIDateFormatting.parse($1.createdAt) ?? .distantPast)
            }
        } catch {
            // Non-blocking — form still works without the list
        }
    }

    private func submit() async {
        let calendar = Calendar.current
        var start = startDate
        var end = endDate

        if allDay {
            start = calendar.startOfDay(for: startDate)
            if let dayEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) {
                end = dayEnd
            }
        }

        guard end > start else {
            error = "End must be after start"
            successMessage = nil
            return
        }

        isSaving = true
        error = nil
        successMessage = nil
        defer { isSaving = false }

        struct Body: Encodable {
            let startAt: String
            let endAt: String
            let allDay: Bool
            let type: String
            let reason: String?
        }

        do {
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            let created: TimeOffRequestDTO = try await env.apiClient.post(
                path: APIPath.scheduleTimeOff,
                body: Body(
                    startAt: VisitDateEditing.isoString(from: start),
                    endAt: VisitDateEditing.isoString(from: end),
                    allDay: allDay,
                    type: type.rawValue,
                    reason: trimmed.isEmpty ? nil : trimmed
                )
            )
            successMessage = created.status == "APPROVED"
                ? "Time off saved."
                : "Request submitted for approval."
            reason = ""
            await loadRecent()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
