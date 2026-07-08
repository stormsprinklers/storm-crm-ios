import SwiftUI

/// Create a new visit/job for a specific customer from the customer profile.
struct CustomerVisitCreateSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let customer: CustomerDTO
    let properties: [CustomerPropertyDTO]
    let employees: [ScheduleEmployeeDTO]
    let serviceAreas: [ScheduleServiceAreaDTO]
    var onCreated: (VisitDTO) async -> Void

    @State private var title = "Service visit"
    @State private var division = "SERVICE"
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var assignedUserId = ""
    @State private var propertyId: String
    @State private var serviceAreaId = ""
    @State private var isCallback = false
    @State private var isSaving = false
    @State private var error: String?

    init(
        customer: CustomerDTO,
        properties: [CustomerPropertyDTO],
        employees: [ScheduleEmployeeDTO],
        serviceAreas: [ScheduleServiceAreaDTO],
        onCreated: @escaping (VisitDTO) async -> Void
    ) {
        self.customer = customer
        self.properties = properties
        self.employees = employees
        self.serviceAreas = serviceAreas
        self.onCreated = onCreated

        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day, .hour], from: Date())
        comps.hour = (comps.hour ?? 8) + 1
        comps.minute = 0
        let start = calendar.date(from: comps) ?? Date().addingTimeInterval(3600)
        _startDate = State(initialValue: start)
        _endDate = State(initialValue: start.addingTimeInterval(3600))

        let primary = properties.first(where: { $0.isPrimary == true }) ?? properties.first
        _propertyId = State(initialValue: primary?.id ?? "")
    }

    private var selectedProperty: CustomerPropertyDTO? {
        properties.first(where: { $0.id == propertyId })
    }

    private var resolvedZip: String? {
        selectedProperty?.zip?.crmNilIfBlank ?? customer.zip?.crmNilIfBlank
    }

    private var isBlocked: Bool { customer.doNotService == true }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (!serviceAreaId.isEmpty || resolvedZip != nil)
            && !isBlocked
    }

    var body: some View {
        NavigationStack {
            Form {
                if isBlocked {
                    Section {
                        Label("This customer is flagged Do Not Service.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Job") {
                    TextField("Title", text: $title)
                    Picker("Type", selection: $division) {
                        Text("Service").tag("SERVICE")
                        Text("Install").tag("INSTALL")
                    }
                    .pickerStyle(.segmented)
                    Toggle("Callback", isOn: $isCallback)
                }

                Section("Times") {
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Assignment") {
                    Picker("Technician", selection: $assignedUserId) {
                        Text("Unassigned").tag("")
                        ForEach(employees) { employee in
                            Text(employee.name).tag(employee.id)
                        }
                    }
                }

                if !properties.isEmpty {
                    Section("Property") {
                        Picker("Property", selection: $propertyId) {
                            Text("None").tag("")
                            ForEach(properties) { property in
                                Text(property.name).tag(property.id)
                            }
                        }
                    }
                }

                Section("Service area") {
                    Picker("Service area", selection: $serviceAreaId) {
                        Text(resolvedZip != nil ? "Auto (from ZIP \(resolvedZip!))" : "Auto").tag("")
                        ForEach(serviceAreas) { area in
                            Text(area.name).tag(area.id)
                        }
                    }
                    if serviceAreaId.isEmpty, resolvedZip == nil {
                        Text("Pick a service area, or add a ZIP to the customer/property so it can be matched automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("New visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await save() } }
                        .disabled(isSaving || !canSave)
                }
            }
        }
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
            let serviceAreaId: String?
            let assignedUserId: String?
            let customerId: String
            let propertyId: String?
            let address: String?
            let city: String?
            let state: String?
            let zip: String?
            let isCallback: Bool
        }

        let property = selectedProperty
        let body = Body(
            title: title.trimmingCharacters(in: .whitespaces),
            startAt: VisitDateEditing.isoString(from: startDate),
            endAt: VisitDateEditing.isoString(from: endDate),
            division: division,
            serviceAreaId: serviceAreaId.isEmpty ? nil : serviceAreaId,
            assignedUserId: assignedUserId.isEmpty ? nil : assignedUserId,
            customerId: customer.id,
            propertyId: propertyId.isEmpty ? nil : propertyId,
            address: property?.address?.crmNilIfBlank ?? customer.address?.crmNilIfBlank,
            city: property?.city?.crmNilIfBlank ?? customer.city?.crmNilIfBlank,
            state: property?.state?.crmNilIfBlank ?? customer.state?.crmNilIfBlank,
            zip: resolvedZip,
            isCallback: isCallback
        )

        do {
            let created: VisitDTO = try await env.apiClient.post(path: APIPath.scheduleJobs, body: body)
            await onCreated(created)
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

/// Create a new (draft) estimate for a specific customer from the customer profile.
struct CustomerEstimateCreateSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let customer: CustomerDTO
    let properties: [CustomerPropertyDTO]
    var onCreated: (EstimateDetailDTO) async -> Void

    @State private var propertyId: String
    @State private var isSaving = false
    @State private var error: String?

    init(
        customer: CustomerDTO,
        properties: [CustomerPropertyDTO],
        onCreated: @escaping (EstimateDetailDTO) async -> Void
    ) {
        self.customer = customer
        self.properties = properties
        self.onCreated = onCreated
        let primary = properties.first(where: { $0.isPrimary == true }) ?? properties.first
        _propertyId = State(initialValue: primary?.id ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    Text(customer.name)
                    if !customer.formattedAddress.isEmpty {
                        Text(customer.formattedAddress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !properties.isEmpty {
                    Section("Property (optional)") {
                        Picker("Property", selection: $propertyId) {
                            Text("None").tag("")
                            ForEach(properties) { property in
                                Text(property.name).tag(property.id)
                            }
                        }
                    }
                }

                Section {
                    Text("Creates a draft estimate. You can add line items on the next screen and send it to the customer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("New estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let body = CreateEstimateBody(
                customerId: customer.id,
                propertyId: propertyId.isEmpty ? nil : propertyId,
                visitId: nil
            )
            let created: EstimateDetailDTO = try await env.apiClient.post(
                path: APIPath.estimates,
                body: body
            )
            await onCreated(created)
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

private extension String {
    var crmNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
