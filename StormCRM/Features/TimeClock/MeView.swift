import SwiftUI

@MainActor
final class TimeClockViewModel: ObservableObject {
    @Published var response: TimeClockResponse?
    @Published var error: String?
    @Published var isLoading = false

    func load(api: APIClient) async {
        isLoading = true
        defer { isLoading = false }
        do {
            response = try await api.get(path: APIPath.timeClock)
        } catch {
            error = (error as? APIError)?.message
        }
    }

    func toggle(api: APIClient) async {
        let action = response?.openEntry == nil ? "in" : "out"
        struct Body: Encodable { let action: String }
        do {
            let _: TimeClockResponse = try await api.post(path: APIPath.timeClock, body: Body(action: action))
            await load(api: api)
        } catch {
            error = (error as? APIError)?.message
        }
    }
}

struct MeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var clock = TimeClockViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Shift clock") {
                    if let open = clock.response?.openEntry {
                        Text("Clocked in since \(open.clockInAt)")
                        Button("Clock out", role: .destructive) {
                            Task { await clock.toggle(api: env.apiClient) }
                        }
                    } else {
                        Button("Clock in") {
                            Task { await clock.toggle(api: env.apiClient) }
                        }
                    }
                    if let hours = clock.response?.todayHours {
                        Text("Today: \(hours, format: .number.precision(.fractionLength(2))) hours")
                    }
                }

                Section {
                    NavigationLink("Search customers") {
                        CustomerSearchView()
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await env.auth.logout() }
                    }
                }
            }
            .navigationTitle("Me")
            .refreshable { await clock.load(api: env.apiClient) }
            .task { await clock.load(api: env.apiClient) }
        }
    }
}

struct CustomerSearchView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var search = ""
    @State private var customers: [CustomerDTO] = []
    @State private var error: String?

    var body: some View {
        List(customers) { customer in
            NavigationLink(value: customer.id) {
                VStack(alignment: .leading) {
                    Text(customer.name)
                    if let phone = customer.phone {
                        Text(phone).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Customers")
        .searchable(text: $search, prompt: "Name or phone")
        .onSubmit(of: .search) { Task { await load() } }
        .navigationDestination(for: String.self) { customerId in
            CustomerDetailView(customerId: customerId)
        }
        .overlay {
            if let error { Text(error).foregroundStyle(.red) }
        }
    }

    private func load() async {
        guard !search.isEmpty else { return }
        do {
            customers = try await env.apiClient.get(
                path: APIPath.customers,
                query: [URLQueryItem(name: "search", value: search)]
            )
        } catch {
            self.error = (error as? APIError)?.message
        }
    }
}

struct CustomerDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    let customerId: String
    @State private var customer: CustomerDTO?
    @State private var error: String?

    var body: some View {
        Form {
            if let customer {
                Section("Contact") {
                    LabeledContent("Name", value: customer.name)
                    if let phone = customer.phone { LabeledContent("Phone", value: phone) }
                    if let email = customer.email { LabeledContent("Email", value: email) }
                }
                Section("Address") {
                    Text([customer.address, customer.city, customer.state, customer.zip]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: ", "))
                }
            } else if let error {
                Text(error).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(customer?.name ?? "Customer")
        .task { await load() }
    }

    private func load() async {
        do {
            customer = try await env.apiClient.get(path: APIPath.customer(customerId))
        } catch {
            self.error = (error as? APIError)?.message
        }
    }
}
