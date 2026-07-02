import SwiftUI

struct VisitScheduleEditSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let visit: VisitDetailDTO
    let canEdit: Bool
    var onSaved: () async -> Void

    @State private var showEditSheet = false

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    StormSectionHeader(title: "Schedule", systemImage: "calendar")
                    Spacer(minLength: 8)
                    if canEdit {
                        Button {
                            showEditSheet = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.body.weight(.medium))
                                .foregroundStyle(StormTheme.sky)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit schedule")
                    }
                }

                LabeledContent("Date") {
                    Text(scheduleDateLabel)
                }
                LabeledContent("Time") {
                    Text(scheduleStartTimeLabel)
                }
                LabeledContent("Window") {
                    Text(scheduleWindowLabel)
                }
                if let tech = visit.assignedUser {
                    LabeledContent("Technician") {
                        HStack(spacing: 8) {
                            EmployeeAvatar(person: tech, size: 24)
                            Text(tech.name)
                        }
                    }
                } else {
                    LabeledContent("Technician") {
                        Text("Unassigned").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            VisitScheduleEditSheet(visit: visit) {
                await onSaved()
            }
        }
    }

    private var scheduleDateLabel: String {
        guard let start = APIDateFormatting.parse(visit.startAt) else {
            return APIDateFormatting.displayString(from: visit.startAt)
        }
        return start.formatted(date: .abbreviated, time: .omitted)
    }

    private var scheduleStartTimeLabel: String {
        guard let start = APIDateFormatting.parse(visit.startAt) else {
            return APIDateFormatting.displayString(from: visit.startAt)
        }
        return start.formatted(date: .omitted, time: .shortened)
    }

    private var scheduleWindowLabel: String {
        guard let start = APIDateFormatting.parse(visit.startAt),
              let end = APIDateFormatting.parse(visit.endAt)
        else {
            return "\(APIDateFormatting.displayString(from: visit.startAt)) – \(APIDateFormatting.displayString(from: visit.endAt))"
        }
        let startTime = start.formatted(date: .omitted, time: .shortened)
        let endTime = end.formatted(date: .omitted, time: .shortened)
        return "\(startTime) – \(endTime)"
    }
}

struct VisitScheduleEditSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let visit: VisitDetailDTO
    var onSaved: () async -> Void

    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var assignedUserId = ""
    @State private var employees: [ScheduleEmployeeDTO] = []
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    Text(visit.title).font(.headline)
                    if let customer = visit.customer {
                        Text(customer.name).foregroundStyle(.secondary)
                    }
                }

                Section("Times") {
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Assignment") {
                    if let selected = selectedEmployee {
                        LabeledContent("Current") {
                            NamedColorChip(person: selected.namedColor)
                        }
                    }
                    if !employeeOptions.isEmpty {
                        Picker("Assigned technician", selection: $assignedUserId) {
                            Text("Unassigned").tag("")
                            ForEach(employeeOptions) { employee in
                                Text(employee.name).tag(employee.id)
                            }
                        }
                    } else {
                        Text("Loading technicians…")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Edit schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .task {
                syncFromVisit()
                employees = (try? await env.apiClient.get(path: APIPath.scheduleFilters) as ScheduleFiltersResponse)?
                    .employees ?? []
            }
        }
    }

    private var employeeOptions: [ScheduleEmployeeDTO] {
        var list = employees
        if let assigned = visit.assignedUser,
           !list.contains(where: { $0.id == assigned.id }) {
            list.insert(
                ScheduleEmployeeDTO(
                    id: assigned.id,
                    name: assigned.name,
                    color: assigned.color,
                    photoUrl: assigned.photoUrl
                ),
                at: 0
            )
        }
        return list
    }

    private var selectedEmployee: ScheduleEmployeeDTO? {
        guard !assignedUserId.isEmpty else { return nil }
        return employeeOptions.first(where: { $0.id == assignedUserId })
    }

    private func syncFromVisit() {
        startDate = VisitDateEditing.date(from: visit.startAt)
        endDate = VisitDateEditing.date(from: visit.endAt)
        assignedUserId = visit.assignedUser?.id ?? ""
    }

    private func save() async {
        guard endDate > startDate else {
            error = "End time must be after start time"
            return
        }
        isSaving = true
        error = nil
        defer { isSaving = false }

        struct Body: Encodable {
            let startAt: String
            let endAt: String
            let assignedUserId: String?
        }
        do {
            let body = Body(
                startAt: VisitDateEditing.isoString(from: startDate),
                endAt: VisitDateEditing.isoString(from: endDate),
                assignedUserId: assignedUserId.isEmpty ? nil : assignedUserId
            )
            let _: VisitDetailDTO = try await env.apiClient.patch(
                path: APIPath.visit(visit.id),
                body: body
            )
            await onSaved()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
