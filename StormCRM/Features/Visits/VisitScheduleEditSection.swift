import SwiftUI

struct VisitScheduleEditSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let visit: VisitDetailDTO
    let canEdit: Bool
    var onSaved: () async -> Void

    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var assignedUserId = ""
    @State private var employees: [ScheduleEmployeeDTO] = []
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                StormSectionHeader(title: "Schedule", systemImage: "calendar")

                if canEdit {
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])

                    if !employees.isEmpty {
                        Picker("Assigned technician", selection: $assignedUserId) {
                            Text("Unassigned").tag("")
                            ForEach(employeeOptions) { employee in
                                Text(employee.name).tag(employee.id)
                            }
                        }
                    }

                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }

                    Button(isSaving ? "Saving…" : "Save schedule") {
                        Task { await save() }
                    }
                    .buttonStyle(StormPrimaryButtonStyle())
                    .disabled(isSaving)
                } else {
                    LabeledContent("Start") {
                        Text(APIDateFormatting.displayString(from: visit.startAt))
                    }
                    LabeledContent("End") {
                        Text(APIDateFormatting.displayString(from: visit.endAt))
                    }
                    if let tech = visit.assignedUser {
                        LabeledContent("Assigned") {
                            NamedColorChip(person: tech)
                        }
                    } else {
                        LabeledContent("Assigned") {
                            Text("Unassigned").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onAppear { syncFromVisit() }
        .onChange(of: visit.startAt) { _, _ in syncFromVisit() }
        .onChange(of: visit.endAt) { _, _ in syncFromVisit() }
        .onChange(of: visit.assignedUser?.id) { _, _ in syncFromVisit() }
        .task {
            guard canEdit else { return }
            employees = (try? await env.apiClient.get(path: APIPath.scheduleFilters) as ScheduleFiltersResponse)?
                .employees ?? []
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
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
