import SwiftUI

@MainActor
final class CustomersListViewModel: ObservableObject {
    @Published var customers: [CustomerDTO] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(api: APIClient, search: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        var query: [URLQueryItem] = [URLQueryItem(name: "status", value: "ALL")]
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            query.append(URLQueryItem(name: "search", value: trimmed))
        }

        do {
            let response: CustomersListResponse = try await api.get(
                path: APIPath.customers,
                query: query
            )
            customers = response.customers
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
            customers = []
        }
    }
}

struct CustomersListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var viewModel = CustomersListViewModel()
    @State private var search = ""
    @State private var showCreate = false
    @State private var searchTask: Task<Void, Never>?
    @State private var navigationPath = NavigationPath()

    private var canCreate: Bool {
        env.auth.user.map { UserRoles.canEditCustomers($0.role) } ?? false
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isLoading && viewModel.customers.isEmpty {
                    ProgressView("Loading customers…")
                } else if viewModel.customers.isEmpty {
                    ContentUnavailableView(
                        "No customers found",
                        systemImage: "person.2",
                        description: Text(viewModel.error ?? "Try a different search or add a customer.")
                    )
                } else {
                    List(viewModel.customers) { customer in
                        NavigationLink(value: CustomerListRoute.detail(id: customer.id)) {
                            CustomerListRow(customer: customer)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Customers")
            .searchable(text: $search, prompt: "Name, phone, or address")
            .toolbar {
                if canCreate {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showCreate = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .navigationDestination(for: CustomerListRoute.self) { route in
                switch route {
                case .detail(let customerId):
                    CustomerDetailView(customerId: customerId)
                }
            }
            .sheet(isPresented: $showCreate) {
                NavigationStack {
                    NewCustomerView { _ in
                        showCreate = false
                        Task { await viewModel.load(api: env.apiClient, search: search) }
                    }
                }
            }
            .refreshable { await viewModel.load(api: env.apiClient, search: search) }
            .task { await viewModel.load(api: env.apiClient, search: search) }
            .onChange(of: env.deepLinkNavigation) { _, navigation in
                guard let navigation else { return }
                if case .customer(let customerId) = navigation {
                    navigationPath.append(CustomerListRoute.detail(id: customerId))
                    env.deepLinkNavigation = nil
                }
            }
            .onChange(of: search) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled else { return }
                    await viewModel.load(api: env.apiClient, search: newValue)
                }
            }
        }
    }
}

struct CustomerListRow: View {
    let customer: CustomerDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(customer.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if customer.isArchived {
                    StormBadge(text: "Archived", style: .warning)
                } else if customer.doNotService == true {
                    StormBadge(text: "DNS", style: .warning)
                }
            }
            if !customer.subtitleLine.isEmpty {
                Text(customer.subtitleLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let counts = countSummary(customer) {
                Text(counts)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func countSummary(_ customer: CustomerDTO) -> String? {
        var parts: [String] = []
        if let count = customer.propertyCount, count > 0 { parts.append("\(count) propert\(count == 1 ? "y" : "ies")") }
        if let count = customer.visitCount, count > 0 { parts.append("\(count) visit\(count == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct NewCustomerView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let onCreated: (String) -> Void

    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var companyName = ""
    @State private var address = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""
    @State private var leadSource = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Customer") {
                TextField("Name", text: $name)
                TextField("Company name (optional)", text: $companyName)
            }
            Section("Contact") {
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }
            Section("Address") {
                TextField("Street", text: $address)
                TextField("City", text: $city)
                TextField("State", text: $state)
                TextField("ZIP", text: $zip)
                    .keyboardType(.numbersAndPunctuation)
            }
            Section("Other") {
                TextField("Lead source", text: $leadSource)
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .navigationTitle("New customer")
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

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = CustomerCreateBody(name: trimmedName)
        body.phone = phone.nilIfBlank
        body.email = email.nilIfBlank
        body.companyName = companyName.nilIfBlank
        body.address = address.nilIfBlank
        body.city = city.nilIfBlank
        body.state = state.nilIfBlank
        body.zip = zip.nilIfBlank
        body.leadSource = leadSource.nilIfBlank

        do {
            let created: CustomerDTO = try await env.apiClient.post(path: APIPath.customers, body: body)
            onCreated(created.id)
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
