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
