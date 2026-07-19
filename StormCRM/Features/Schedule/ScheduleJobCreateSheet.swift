import SwiftUI

/// Quick "add job" sheet launched by tapping an empty slot on the schedule timeline.
struct ScheduleJobCreateSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let employees: [ScheduleEmployeeDTO]
    var onCreated: () async -> Void

    @State private var title = "Service visit"
    @State private var division = "SERVICE"
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var assignedUserId: String

    @State private var customerSearch = ""
    @State private var customerResults: [CustomerDTO] = []
    @State private var selectedCustomer: CustomerDTO?
    @State private var properties: [CustomerPropertyDTO] = []
    @State private var propertyId = ""
    @State private var isSearchingCustomers = false
    @State private var isLoadingProperties = false
    @State private var searchTask: Task<Void, Never>?

    @State private var isSaving = false
    @State private var error: String?

    init(
        start: Date,
        defaultAssignedUserId: String?,
        employees: [ScheduleEmployeeDTO],
        onCreated: @escaping () async -> Void
    ) {
        self.employees = employees
        self.onCreated = onCreated
        _startDate = State(initialValue: start)
        _endDate = State(initialValue: start.addingTimeInterval(3600))
        _assignedUserId = State(initialValue: defaultAssignedUserId ?? "")
    }

    private var selectedProperty: CustomerPropertyDTO? {
        properties.first(where: { $0.id == propertyId })
    }

    /// Only prompt when the customer has more than one property.
    private var showsPropertyPicker: Bool {
        properties.count > 1
    }

    private var canSave: Bool {
        guard selectedCustomer != nil else { return false }
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if showsPropertyPicker {
            return !propertyId.isEmpty
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    if let selectedCustomer {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedCustomer.name)
                                    .font(.body.weight(.semibold))
                                if !selectedCustomer.formattedAddress.isEmpty {
                                    Text(selectedCustomer.formattedAddress)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Change") {
                                clearCustomerSelection()
                            }
                            .font(.subheadline)
                        }

                        if isLoadingProperties {
                            ProgressView("Loading properties…")
                        } else if showsPropertyPicker {
                            Picker("Property", selection: $propertyId) {
                                Text("Select property…").tag("")
                                ForEach(properties) { property in
                                    Text(propertyPickerLabel(property)).tag(property.id)
                                }
                            }
                        } else if let only = properties.first {
                            LabeledContent("Property", value: propertyPickerLabel(only))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        TextField("Search customers", text: $customerSearch)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()

                        if isSearchingCustomers {
                            ProgressView()
                        } else if customerResults.isEmpty, !customerSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("No customers match that search.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(customerResults.prefix(12)) { customer in
                                Button {
                                    Task { await selectCustomer(customer) }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(customer.name)
                                            .foregroundStyle(.primary)
                                        if !customer.formattedAddress.isEmpty {
                                            Text(customer.formattedAddress)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

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
            .onChange(of: customerSearch) { _, value in
                guard selectedCustomer == nil else { return }
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    guard !Task.isCancelled else { return }
                    await searchCustomers(value)
                }
            }
        }
    }

    private func propertyPickerLabel(_ property: CustomerPropertyDTO) -> String {
        let address = property.formattedAddress
        if address.isEmpty { return property.name }
        return "\(property.name) — \(address)"
    }

    private func clearCustomerSelection() {
        selectedCustomer = nil
        properties = []
        propertyId = ""
        customerSearch = ""
        customerResults = []
    }

    private func selectCustomer(_ customer: CustomerDTO) async {
        selectedCustomer = customer
        customerSearch = ""
        customerResults = []
        if title == "Service visit" || title.trimmingCharacters(in: .whitespaces).isEmpty {
            title = customer.name
        }
        await loadProperties(for: customer.id)
    }

    private func searchCustomers(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            customerResults = []
            return
        }
        isSearchingCustomers = true
        defer { isSearchingCustomers = false }
        do {
            let response: CustomersListResponse = try await env.apiClient.get(
                path: APIPath.customers,
                query: [
                    URLQueryItem(name: "status", value: "ALL"),
                    URLQueryItem(name: "search", value: trimmed),
                ]
            )
            customerResults = response.customers
        } catch {
            customerResults = []
        }
    }

    private func loadProperties(for customerId: String) async {
        isLoadingProperties = true
        defer { isLoadingProperties = false }
        do {
            let loaded: [CustomerPropertyDTO] = try await env.apiClient.get(
                path: APIPath.customerProperties(customerId)
            )
            properties = loaded
            if loaded.count == 1 {
                propertyId = loaded[0].id
            } else if loaded.count > 1 {
                let primary = loaded.first(where: { $0.isPrimary == true }) ?? loaded.first
                propertyId = primary?.id ?? ""
            } else {
                propertyId = ""
            }
        } catch {
            properties = []
            propertyId = ""
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func save() async {
        guard let customer = selectedCustomer else {
            error = "Select a customer"
            return
        }
        guard endDate > startDate else {
            error = "End time must be after start time"
            return
        }
        if showsPropertyPicker, propertyId.isEmpty {
            error = "Select a property"
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
        }

        do {
            var assignee = assignedUserId.isEmpty ? nil : assignedUserId
            if let role = env.auth.user?.role, UserRoles.isFieldRole(role), let me = env.auth.user?.id {
                assignee = me
            }

            let property = selectedProperty
            // Prefer the single auto-selected property when the picker is hidden.
            let resolvedPropertyId: String? = {
                if !propertyId.isEmpty { return propertyId }
                if properties.count == 1 { return properties[0].id }
                return nil
            }()

            let body = Body(
                title: title.trimmingCharacters(in: .whitespaces),
                startAt: VisitDateEditing.isoString(from: startDate),
                endAt: VisitDateEditing.isoString(from: endDate),
                division: division,
                // Service area is resolved server-side from the customer/property ZIP.
                serviceAreaId: nil,
                assignedUserId: assignee,
                customerId: customer.id,
                propertyId: resolvedPropertyId,
                address: property?.address?.crmNilIfBlank ?? customer.address?.crmNilIfBlank,
                city: property?.city?.crmNilIfBlank ?? customer.city?.crmNilIfBlank,
                state: property?.state?.crmNilIfBlank ?? customer.state?.crmNilIfBlank,
                zip: property?.zip?.crmNilIfBlank ?? customer.zip?.crmNilIfBlank
            )
            let _: VisitDTO = try await env.apiClient.post(path: APIPath.scheduleJobs, body: body)
            await onCreated()
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
