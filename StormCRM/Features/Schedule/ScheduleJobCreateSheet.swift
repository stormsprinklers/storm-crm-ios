import SwiftUI

/// Quick "add job" sheet launched by tapping an empty slot on the schedule timeline.
struct ScheduleJobCreateSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let employees: [ScheduleEmployeeDTO]
    let serviceAreas: [ScheduleServiceAreaDTO]
    var onCreated: () async -> Void

    @State private var title = "Service visit"
    @State private var division = "SERVICE"
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var assignedUserId: String
    @State private var serviceAreaId: String
    @State private var isSaving = false
    @State private var error: String?

    init(
        start: Date,
        defaultAssignedUserId: String?,
        employees: [ScheduleEmployeeDTO],
        serviceAreas: [ScheduleServiceAreaDTO],
        onCreated: @escaping () async -> Void
    ) {
        self.employees = employees
        self.serviceAreas = serviceAreas
        self.onCreated = onCreated
        _startDate = State(initialValue: start)
        _endDate = State(initialValue: start.addingTimeInterval(3600))
        _assignedUserId = State(initialValue: defaultAssignedUserId ?? "")
        _serviceAreaId = State(initialValue: serviceAreas.first?.id ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    TextField("Title", text: $title)
                    Picker("Type", selection: $division) {
                        Text("Service").tag("SERVICE")
                        Text("Install").tag("INSTALL")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Times") {
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Assignment") {
                    if let role = env.auth.user?.role, UserRoles.isFieldRole(role) {
                        Text("Assigned to you")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Technician", selection: $assignedUserId) {
                            Text("Unassigned").tag("")
                            ForEach(employees) { employee in
                                Text(employee.name).tag(employee.id)
                            }
                        }
                    }
                }

                Section("Service area") {
                    if serviceAreas.isEmpty {
                        Text("No service areas configured. Add one in the web CRM first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Service area", selection: $serviceAreaId) {
                            ForEach(serviceAreas) { area in
                                Text(area.name).tag(area.id)
                            }
                        }
                    }
                }

                Section {
                    Text("You can add a customer, line items, and notes after the job is created.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Add job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await save() } }
                        .disabled(isSaving || !canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !serviceAreaId.isEmpty
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
            let title: String
            let startAt: String
            let endAt: String
            let division: String
            let serviceAreaId: String
            let assignedUserId: String?
        }
        do {
            let assignee = assignedUserId.isEmpty ? nil : assignedUserId
            if let role = env.auth.user?.role, UserRoles.isFieldRole(role), let me = env.auth.user?.id {
                assignee = me
            }
            let body = Body(
                title: title.trimmingCharacters(in: .whitespaces),
                startAt: VisitDateEditing.isoString(from: startDate),
                endAt: VisitDateEditing.isoString(from: endDate),
                division: division,
                serviceAreaId: serviceAreaId,
                assignedUserId: assignee
            )
            let _: VisitDTO = try await env.apiClient.post(path: APIPath.scheduleJobs, body: body)
            await onCreated()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
