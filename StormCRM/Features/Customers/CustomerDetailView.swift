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
}

struct CustomerDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    let customerId: String

    @StateObject private var viewModel = CustomerDetailViewModel()
    @State private var showEdit = false
    @State private var showSmsCompose = false
    @State private var noteDraft = ""
    @State private var isAddingNote = false

    private var userRole: String? { env.auth.user?.role }
    private var canEdit: Bool { userRole.map { UserRoles.canEditCustomers($0) } ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let customer = viewModel.customer {
                    if customer.doNotService == true {
                        DoNotServiceBanner()
                    }

                    CustomerContactCard(
                        customer: customer,
                        voice: env.voice,
                        onMessage: { showSmsCompose = true }
                    )

                    if !customer.formattedAddress.isEmpty {
                        CustomerAddressCard(address: customer.formattedAddress)
                    }

                    CustomerStatsCard(customer: customer)

                    if let role = userRole {
                        CustomerServicePlansSection(
                            customerId: customerId,
                            properties: viewModel.properties,
                            userRole: role
                        )
                    }

                    CustomerPropertiesSection(
                        customerId: customerId,
                        properties: viewModel.properties
                    )

                    CustomerHistorySection(history: viewModel.history)

                    CustomerNotesSection(
                        notes: viewModel.notes,
                        noteDraft: $noteDraft,
                        isAddingNote: isAddingNote,
                        onAdd: { Task { await submitNote() } }
                    )
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
                        try await viewModel.saveCustomer(
                            api: env.apiClient,
                            customerId: customerId,
                            update: update
                        )
                        showEdit = false
                    }
                }
            }
        }
        .sheet(isPresented: $showSmsCompose) {
            if let customer = viewModel.customer {
                NavigationStack {
                    NewSmsConversationView(
                        scope: .customers,
                        initialContact: InboxContactDTO(
                            id: customer.id,
                            name: customer.name,
                            phone: customer.phone,
                            email: customer.email
                        )
                    ) { _ in
                        showSmsCompose = false
                    }
                }
            }
        }
        .refreshable { await viewModel.load(api: env.apiClient, customerId: customerId) }
        .task { await viewModel.load(api: env.apiClient, customerId: customerId) }
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
                            Label("CRM text", systemImage: "message.fill")
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
                if let tags = customer.tags, !tags.isEmpty {
                    FlowTagsView(tags: tags)
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
                if let url = mapsURL(address) {
                    Link("Open in Maps", destination: url)
                        .font(.subheadline)
                        .foregroundStyle(StormTheme.sky)
                }
            }
        }
    }

    private func mapsURL(_ address: String) -> URL? {
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? address
        return URL(string: "http://maps.apple.com/?q=\(encoded)")
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

struct CustomerPropertiesSection: View {
    let customerId: String
    let properties: [CustomerPropertyDTO]

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 10) {
                StormSectionHeader(title: "Properties", systemImage: "house")
                if properties.isEmpty {
                    Text("No properties on file").foregroundStyle(.secondary)
                } else {
                    ForEach(properties) { property in
                        NavigationLink {
                            PropertyDetailView(customerId: customerId, property: property)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(property.name).font(.subheadline.weight(.medium))
                                        if property.isPrimary == true {
                                            StormBadge(text: "Primary", style: .accent)
                                        }
                                    }
                                    if let status = property.irrigationMapStatus {
                                        Text("Irrigation: \(status.replacingOccurrences(of: "_", with: " "))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        if property.id != properties.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

struct CustomerHistorySection: View {
    let history: CustomerHistoryDTO?

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 10) {
                StormSectionHeader(title: "History", systemImage: "clock.arrow.circlepath")
                if let history {
                    Text("\(history.pastVisitCount) visit\(history.pastVisitCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if history.visits.isEmpty {
                        Text("No visits yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(history.visits.prefix(15)) { visit in
                            NavigationLink {
                                VisitDetailView(visitId: visit.id)
                            } label: {
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
                                    StormBadge(text: visit.status)
                                }
                            }
                            .buttonStyle(.plain)
                            if visit.id != history.visits.prefix(15).last?.id {
                                Divider()
                            }
                        }
                    }

                    if !history.estimatesWithoutVisit.isEmpty {
                        Text("Estimates without visit")
                            .font(.caption.weight(.semibold))
                            .padding(.top, 8)
                        ForEach(history.estimatesWithoutVisit.prefix(5)) { estimate in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(estimate.status.replacingOccurrences(of: "_", with: " "))
                                        .font(.subheadline)
                                    Text(APIDateFormatting.displayString(from: estimate.createdAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(estimate.total, format: .currency(code: "USD"))
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                    }

                    if let linked = history.estimatesLinkedToVisits, !linked.isEmpty {
                        Text("Estimates on visits")
                            .font(.caption.weight(.semibold))
                            .padding(.top, 8)
                        ForEach(linked.prefix(5)) { estimate in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(estimate.visitTitle ?? "Visit estimate")
                                        .font(.subheadline)
                                    Text(estimate.status.replacingOccurrences(of: "_", with: " "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(estimate.total, format: .currency(code: "USD"))
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                    }
                } else {
                    Text("No history loaded").foregroundStyle(.secondary)
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
                TextField("Tags (comma-separated)", text: $tagsText)
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
        update.tags = tags
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

struct PropertyDetailView: View {
    let customerId: String
    let property: CustomerPropertyDTO

    var body: some View {
        List {
            Section("Property") {
                LabeledContent("Name", value: property.name)
                if let address = propertyAddress {
                    LabeledContent("Address", value: address)
                }
                if let zones = property.irrigationZoneCount {
                    LabeledContent("Irrigation zones", value: "\(zones)")
                }
                if let shutoff = property.shutoffValveLocation {
                    LabeledContent("Shutoff", value: shutoff)
                }
                if let controller = property.controllerLocation {
                    LabeledContent("Controller", value: controller)
                }
            }

            Section {
                NavigationLink {
                    IrrigationDetailView(
                        customerId: customerId,
                        propertyId: property.id,
                        propertyName: property.name
                    )
                } label: {
                    Label("Irrigation map & program", systemImage: "drop.fill")
                }
                NavigationLink {
                    IrrigationMapEditorView(
                        customerId: customerId,
                        propertyId: property.id,
                        propertyName: property.name
                    )
                } label: {
                    Label("Edit irrigation map", systemImage: "pencil")
                }
            }
        }
        .navigationTitle(property.name)
    }

    private var propertyAddress: String? {
        [property.address, property.city, property.state, property.zip]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
            .nilIfEmpty
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var nilIfEmpty: String? { isEmpty ? nil : self }
}
