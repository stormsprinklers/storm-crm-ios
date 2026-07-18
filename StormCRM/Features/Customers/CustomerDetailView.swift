import SwiftUI

@MainActor
final class CustomerDetailViewModel: ObservableObject {
    @Published var customer: CustomerDTO?
    @Published var properties: [CustomerPropertyDTO] = []
    @Published var history: CustomerHistoryDTO?
    @Published var notes: [CustomerNoteDTO] = []
    @Published var error: String?
    @Published var isLoading = false

    func load(api: APIClient, customerId: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            async let customerTask: CustomerDTO = api.get(path: APIPath.customer(customerId))
            async let propertiesTask: [CustomerPropertyDTO] = api.get(path: APIPath.customerProperties(customerId))
            async let historyTask: CustomerHistoryDTO = api.get(path: APIPath.customerHistory(customerId))
            async let notesTask: [CustomerNoteDTO] = api.get(path: APIPath.customerNotes(customerId))

            customer = try await customerTask
            properties = try await propertiesTask
            history = try await historyTask
            notes = (try? await notesTask) ?? []
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func addNote(api: APIClient, customerId: String, body: String) async throws {
        struct Body: Encodable { let body: String }
        let note: CustomerNoteDTO = try await api.post(
            path: APIPath.customerNotes(customerId),
            body: Body(body: body)
        )
        notes.insert(note, at: 0)
    }

    func saveCustomer(api: APIClient, customerId: String, update: CustomerUpdateBody) async throws -> CustomerDTO {
        let updated: CustomerDTO = try await api.patch(
            path: APIPath.customer(customerId),
            body: update
        )
        customer = updated
        return updated
    }

    func updateTags(api: APIClient, customerId: String, tags: [String]) async throws {
        var update = CustomerUpdateBody()
        update.tags = tags
        customer = try await saveCustomer(api: api, customerId: customerId, update: update)
    }

    func updateDoNotService(api: APIClient, customerId: String, doNotService: Bool) async throws {
        var update = CustomerUpdateBody()
        update.doNotService = doNotService
        customer = try await saveCustomer(api: api, customerId: customerId, update: update)
    }
}

struct CustomerDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    let customerId: String

    @StateObject private var viewModel = CustomerDetailViewModel()
    @State private var showEdit = false
    @State private var showCreateVisit = false
    @State private var showCreateEstimate = false
    @State private var scheduleEmployees: [ScheduleEmployeeDTO] = []
    @State private var scheduleServiceAreas: [ScheduleServiceAreaDTO] = []
    @State private var createdVisit: CreatedVisitRoute?
    @State private var createdEstimate: CreatedEstimateRoute?
    @State private var noteDraft = ""
    @State private var isAddingNote = false

    private struct CreatedVisitRoute: Identifiable, Hashable { let id: String }
    private struct CreatedEstimateRoute: Identifiable, Hashable { let id: String }

    private var canCreateVisit: Bool {
        // Field techs may self-schedule; office roles already could.
        userRole != nil
    }

    private var userRole: String? { env.auth.user?.role }
    private var canEdit: Bool { userRole.map { UserRoles.canEditCustomers($0) } ?? false }
    private var canEditTags: Bool { userRole.map { UserRoles.canEditCustomerTags($0) } ?? false }
    private var canFlagDoNotService: Bool { userRole.map { UserRoles.canFlagDoNotService($0) } ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let customer = viewModel.customer {
                    if customer.doNotService == true {
                        DoNotServiceBanner()
                    }

                    CustomerStatsCard(customer: customer)

                    CustomerContactCard(
                        customer: customer,
                        voice: env.voice,
                        onMessage: {
                            env.openCustomerSmsInbox(
                                customerId: customer.id,
                                name: customer.name,
                                phone: customer.phone
                            )
                        }
                    )

                    CustomerPropertiesSection(
                        customerId: customerId,
                        properties: viewModel.properties
                    )

                    if viewModel.properties.isEmpty, !customer.formattedAddress.isEmpty {
                        CustomerAddressCard(address: customer.formattedAddress)
                    }

                    if canEditTags || canFlagDoNotService {
                        CustomerTagsAndFlagsSection(
                            customer: customer,
                            canEditTags: canEditTags,
                            canFlagDoNotService: canFlagDoNotService,
                            onTagsUpdated: { tags in
                                try await viewModel.updateTags(
                                    api: env.apiClient,
                                    customerId: customerId,
                                    tags: tags
                                )
                            },
                            onDoNotServiceUpdated: { flagged in
                                try await viewModel.updateDoNotService(
                                    api: env.apiClient,
                                    customerId: customerId,
                                    doNotService: flagged
                                )
                            },
                            onError: { message in
                                viewModel.error = message
                            }
                        )
                    } else if let tags = customer.tags, !tags.isEmpty {
                        StormCard {
                            VStack(alignment: .leading, spacing: 8) {
                                StormSectionHeader(title: "Tags", systemImage: "tag")
                                FlowTagsView(tags: tags)
                            }
                        }
                    }

                    if let role = userRole {
                        CustomerServicePlansSection(
                            customerId: customerId,
                            properties: viewModel.properties,
                            userRole: role
                        )
                    }

                    CustomerHistorySection(history: viewModel.history)

                    CustomerNotesSection(
                        notes: viewModel.notes,
                        noteDraft: $noteDraft,
                        isAddingNote: isAddingNote,
                        onAdd: { Task { await submitNote() } }
                    )

                    CustomerAttachmentsSection(customerId: customerId)
                } else if viewModel.isLoading {
                    ProgressView("Loading customer…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }

                if let error = viewModel.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .padding()
        }
        .background(StormTheme.page.ignoresSafeArea())
        .navigationTitle(viewModel.customer?.name ?? "Customer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit, viewModel.customer != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showCreateVisit = true
                        } label: {
                            Label("New visit", systemImage: "calendar.badge.plus")
                        }
                        .disabled(!canCreateVisit)
                        Button {
                            showCreateEstimate = true
                        } label: {
                            Label("New estimate", systemImage: "doc.text")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEdit = true }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let customer = viewModel.customer, let role = userRole {
                NavigationStack {
                    CustomerEditView(
                        customer: customer,
                        userRole: role
                    ) { update in
                        _ = try await viewModel.saveCustomer(
                            api: env.apiClient,
                            customerId: customerId,
                            update: update
                        )
                        showEdit = false
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateVisit) {
            if let customer = viewModel.customer {
                CustomerVisitCreateSheet(
                    customer: customer,
                    properties: viewModel.properties,
                    employees: scheduleEmployees,
                    serviceAreas: scheduleServiceAreas
                ) { created in
                    await viewModel.load(api: env.apiClient, customerId: customerId)
                    navigate(afterDelay: { createdVisit = CreatedVisitRoute(id: created.id) })
                }
                .environmentObject(env)
            }
        }
        .sheet(isPresented: $showCreateEstimate) {
            if let customer = viewModel.customer {
                CustomerEstimateCreateSheet(
                    customer: customer,
                    properties: viewModel.properties
                ) { created in
                    await viewModel.load(api: env.apiClient, customerId: customerId)
                    navigate(afterDelay: { createdEstimate = CreatedEstimateRoute(id: created.id) })
                }
                .environmentObject(env)
            }
        }
        .navigationDestination(item: $createdVisit) { route in
            VisitDetailView(visitId: route.id)
        }
        .navigationDestination(item: $createdEstimate) { route in
            EstimateDetailView(estimateId: route.id)
        }
        .refreshable { await viewModel.load(api: env.apiClient, customerId: customerId) }
        .task { await viewModel.load(api: env.apiClient, customerId: customerId) }
        .task { await loadScheduleFilters() }

    }

    private func loadScheduleFilters() async {
        guard canEdit, scheduleEmployees.isEmpty else { return }
        if let filters = try? await env.apiClient.get(path: APIPath.scheduleFilters) as ScheduleFiltersResponse {
            scheduleEmployees = filters.employees ?? []
            scheduleServiceAreas = filters.serviceAreas ?? []
        }
    }

    /// Push the newly created record once the create sheet finishes dismissing.
    private func navigate(afterDelay work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { work() }
    }

    private func submitNote() async {
        let body = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isAddingNote = true
        defer { isAddingNote = false }
        do {
            try await viewModel.addNote(api: env.apiClient, customerId: customerId, body: body)
            noteDraft = ""
        } catch {
            viewModel.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct CustomerContactCard: View {
    let customer: CustomerDTO
    @ObservedObject var voice: VoiceManager
    let onMessage: () -> Void

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 10) {
                StormSectionHeader(title: "Contact", systemImage: "person.crop.circle")
                Text(customer.name)
                    .font(.title3.weight(.semibold))
                if let company = customer.companyName, !company.isEmpty {
                    Text(company).foregroundStyle(.secondary)
                }
                if let phone = customer.phone, !phone.isEmpty {
                    HStack(spacing: 16) {
                        Button(action: onMessage) {
                            Label("Text", systemImage: "message.fill")
                        }
                        Button {
                            Task { await voice.call(phone: phone, customerId: customer.id) }
                        } label: {
                            Label("Call", systemImage: "phone.fill")
                        }
                    }
                    .font(.subheadline)
                    .buttonStyle(.plain)
                    .foregroundStyle(StormTheme.sky)
                    Text(phone).font(.caption).foregroundStyle(.secondary)
                }
                if let email = customer.email, !email.isEmpty {
                    Link(destination: URL(string: "mailto:\(email)")!) {
                        Label(email, systemImage: "envelope")
                    }
                    .font(.subheadline)
                }
                if let source = customer.leadSource, !source.isEmpty {
                    LabeledContent("Lead source", value: source)
                        .font(.caption)
                }
            }
        }
    }
}

struct CustomerAddressCard: View {
    let address: String

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Address", systemImage: "mappin.and.ellipse")
                Text(address)
                if let url = AppleMapsURL.directionsURL(latitude: nil, longitude: nil, address: address) {
                    Link("Open in Maps", destination: url)
                        .font(.subheadline)
                        .foregroundStyle(StormTheme.sky)
                }
            }
        }
    }
}

struct CustomerStatsCard: View {
    let customer: CustomerDTO

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Summary", systemImage: "chart.bar.doc.horizontal")
                HStack(spacing: 16) {
                    statItem("Properties", customer.propertyCount)
                    statItem("Visits", customer.visitCount)
                    statItem("Estimates", customer.estimateCount)
                    statItem("Invoices", customer.invoiceCount)
                }
                if customer.isArchived {
                    StormBadge(text: "Archived", style: .warning)
                }
            }
        }
    }

    private func statItem(_ label: String, _ value: Int?) -> some View {
        VStack(spacing: 2) {
            Text("\(value ?? 0)")
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CustomerHistorySection: View {
    let history: CustomerHistoryDTO?

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "History", systemImage: "clock.arrow.circlepath")

                if let history {
                    DisclosureGroup {
                        historyVisitsContent(history)
                    } label: {
                        historyCategoryLabel(
                            "Visits",
                            count: history.visits.isEmpty ? history.pastVisitCount : history.visits.count,
                            systemImage: "calendar"
                        )
                    }

                    DisclosureGroup {
                        historyEstimatesContent(history)
                    } label: {
                        historyCategoryLabel(
                            "Estimates",
                            count: estimateCount(history),
                            systemImage: "doc.text"
                        )
                    }

                    DisclosureGroup {
                        historyInvoicesContent(history)
                    } label: {
                        historyCategoryLabel(
                            "Invoices",
                            count: history.invoices?.count ?? 0,
                            systemImage: "dollarsign.circle"
                        )
                    }
                } else {
                    Text("No history loaded")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func estimateCount(_ history: CustomerHistoryDTO) -> Int {
        history.estimatesWithoutVisit.count + (history.estimatesLinkedToVisits?.count ?? 0)
    }

    private func historyCategoryLabel(_ title: String, count: Int, systemImage: String) -> some View {
        Label {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(StormTheme.navy)
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(StormTheme.sky)
        }
    }

    @ViewBuilder
    private func historyVisitsContent(_ history: CustomerHistoryDTO) -> some View {
        if history.visits.isEmpty {
            Text("No visits yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(history.visits.prefix(15).enumerated()), id: \.element.id) { index, visit in
                    NavigationLink(value: CustomerHistoryDestination.visit(visit.id)) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(visit.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(StormTheme.navy)
                                Text(APIDateFormatting.displayString(from: visit.startAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let tech = visit.assignedUserName {
                                    Text(tech).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            StormBadge(text: visit.status.visitDisplayLabel)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    if index < min(history.visits.count, 15) - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func historyEstimatesContent(_ history: CustomerHistoryDTO) -> some View {
        let standalone = Array(history.estimatesWithoutVisit.prefix(5))
        let linked = Array((history.estimatesLinkedToVisits ?? []).prefix(5))

        if standalone.isEmpty && linked.isEmpty {
            Text("No estimates yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(standalone.enumerated()), id: \.element.id) { index, estimate in
                    NavigationLink(value: CustomerHistoryDestination.estimate(estimate.id)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(estimate.status.replacingOccurrences(of: "_", with: " "))
                                    .font(.subheadline)
                                    .foregroundStyle(StormTheme.navy)
                                Text(APIDateFormatting.displayString(from: estimate.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(estimate.total, format: .currency(code: "USD"))
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    if index < standalone.count - 1 || !linked.isEmpty {
                        Divider()
                    }
                }

                ForEach(Array(linked.enumerated()), id: \.element.id) { index, estimate in
                    NavigationLink(value: CustomerHistoryDestination.estimate(estimate.id)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(estimate.visitTitle ?? "Visit estimate")
                                    .font(.subheadline)
                                    .foregroundStyle(StormTheme.navy)
                                Text(estimate.status.replacingOccurrences(of: "_", with: " "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(estimate.total, format: .currency(code: "USD"))
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    if index < linked.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func historyInvoicesContent(_ history: CustomerHistoryDTO) -> some View {
        let invoices = Array((history.invoices ?? []).prefix(10))
        if invoices.isEmpty {
            Text("No invoices yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(invoices.enumerated()), id: \.element.id) { index, invoice in
                    NavigationLink(value: CustomerHistoryDestination.invoice(invoice.id)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invoice.invoiceNumber)
                                    .font(.subheadline)
                                    .foregroundStyle(StormTheme.navy)
                                Text(invoice.status.replacingOccurrences(of: "_", with: " "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let visitTitle = invoice.visitTitle {
                                    Text(visitTitle)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Text(invoice.total, format: .currency(code: "USD"))
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    if index < invoices.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}

struct CustomerNotesSection: View {
    let notes: [CustomerNoteDTO]
    @Binding var noteDraft: String
    let isAddingNote: Bool
    let onAdd: () -> Void

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 10) {
                StormSectionHeader(title: "Notes", systemImage: "note.text")
                HStack(alignment: .bottom) {
                    TextField("Add a note…", text: $noteDraft, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                    Button(action: onAdd) {
                        if isAddingNote {
                            ProgressView()
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                    }
                    .disabled(isAddingNote || noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if notes.isEmpty {
                    Text("No notes yet").foregroundStyle(.secondary)
                } else {
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(note.author.name)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(APIDateFormatting.displayString(from: note.createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(note.body)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                        if note.id != notes.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

struct CustomerEditView: View {
    @Environment(\.dismiss) private var dismiss

    let customer: CustomerDTO
    let userRole: String
    let onSave: (CustomerUpdateBody) async throws -> Void

    @State private var name: String
    @State private var phone: String
    @State private var email: String
    @State private var companyName: String
    @State private var address: String
    @State private var city: String
    @State private var state: String
    @State private var zip: String
    @State private var leadSource: String
    @State private var tagsText: String
    @State private var doNotService: Bool
    @State private var isArchived: Bool
    @State private var isSaving = false
    @State private var error: String?

    init(customer: CustomerDTO, userRole: String, onSave: @escaping (CustomerUpdateBody) async throws -> Void) {
        self.customer = customer
        self.userRole = userRole
        self.onSave = onSave
        _name = State(initialValue: customer.name)
        _phone = State(initialValue: customer.phone ?? "")
        _email = State(initialValue: customer.email ?? "")
        _companyName = State(initialValue: customer.companyName ?? "")
        _address = State(initialValue: customer.address ?? "")
        _city = State(initialValue: customer.city ?? "")
        _state = State(initialValue: customer.state ?? "")
        _zip = State(initialValue: customer.zip ?? "")
        _leadSource = State(initialValue: customer.leadSource ?? "")
        _tagsText = State(initialValue: (customer.tags ?? []).joined(separator: ", "))
        _doNotService = State(initialValue: customer.doNotService ?? false)
        _isArchived = State(initialValue: customer.isArchived)
    }

    var body: some View {
        Form {
            Section("Customer") {
                TextField("Name", text: $name)
                TextField("Company name", text: $companyName)
            }
            Section("Contact") {
                TextField("Phone", text: $phone).keyboardType(.phonePad)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }
            Section("Address") {
                TextField("Street", text: $address)
                TextField("City", text: $city)
                TextField("State", text: $state)
                TextField("ZIP", text: $zip)
            }
            Section("Other") {
                TextField("Lead source", text: $leadSource)
            }
            if UserRoles.canEditCustomerTags(userRole) {
                Section("Tags") {
                    TextField("Tags (comma-separated)", text: $tagsText)
                    Text("You can also add and remove tags on the customer profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if UserRoles.canFlagDoNotService(userRole) {
                Section("Flags") {
                    Toggle("Do not service", isOn: $doNotService)
                }
            }
            if UserRoles.canManageCustomerStatus(userRole) {
                Section("Status") {
                    Toggle("Archived", isOn: $isArchived)
                }
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .navigationTitle("Edit customer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }

        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var update = CustomerUpdateBody()
        update.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        update.phone = phone.nilIfBlank
        update.email = email.nilIfBlank
        update.companyName = companyName.nilIfBlank
        update.address = address.nilIfBlank
        update.city = city.nilIfBlank
        update.state = state.nilIfBlank
        update.zip = zip.nilIfBlank
        update.leadSource = leadSource.nilIfBlank
        if UserRoles.canEditCustomerTags(userRole) {
            update.tags = tags
        }
        if UserRoles.canFlagDoNotService(userRole) {
            update.doNotService = doNotService
        }
        if UserRoles.canManageCustomerStatus(userRole) {
            update.status = isArchived ? "ARCHIVED" : "ACTIVE"
        }

        do {
            _ = try await onSave(update)
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct FlowTagsView: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    StormBadge(text: tag, style: .neutral)
                }
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var nilIfEmpty: String? { isEmpty ? nil : self }
}
