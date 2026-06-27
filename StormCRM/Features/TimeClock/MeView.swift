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
            self.error = (error as? APIError)?.message
        }
    }

    func toggle(api: APIClient) async {
        let action = response?.openEntry == nil ? "in" : "out"
        struct Body: Encodable { let action: String }
        do {
            let _: TimeClockResponse = try await api.post(path: APIPath.timeClock, body: Body(action: action))
            await load(api: api)
        } catch {
            self.error = (error as? APIError)?.message
        }
    }
}

struct MeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var auth: AuthManager
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
                    Button("Sign out", role: .destructive) {
                        Task { await auth.logout() }
                    }
                }
            }
            .navigationTitle("Me")
            .refreshable { await clock.load(api: env.apiClient) }
            .task { await clock.load(api: env.apiClient) }
        }
    }
}
