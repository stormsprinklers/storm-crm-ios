import SwiftUI

struct ScheduleJobEditSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let job: VisitDTO
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
                    Text(job.title).font(.headline)
                    if let customer = job.customer {
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
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .task {
                syncFromJob()
                employees = (try? await env.apiClient.get(path: APIPath.scheduleFilters) as ScheduleFiltersResponse)?
                    .employees ?? []
            }
        }
    }

    private var employeeOptions: [ScheduleEmployeeDTO] {
        var list = employees
        if let assigned = job.assignedUser,
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

    private func syncFromJob() {
        startDate = VisitDateEditing.date(from: job.startAt)
        endDate = VisitDateEditing.date(from: job.endAt)
        assignedUserId = job.assignedUser?.id ?? ""
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
                path: APIPath.visit(job.id),
                body: body
            )
            await onSaved()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
