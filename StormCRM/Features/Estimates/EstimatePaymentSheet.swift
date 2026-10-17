import SwiftUI

struct EstimatePaymentSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let estimateId: String
    var onUpdated: () async -> Void
    @State private var amount = 0.0
    @State private var balance = 0.0
    @State private var method = "CARD"
    @State private var loading = true
    @State private var error: String?
    @State private var checkoutURL: URL?
    @State private var reference = UUID().uuidString
    var body: some View {
        NavigationStack {
            Form {
                if loading { ProgressView() }
                LabeledContent("Balance due", value: balance.formatted(.currency(code: "USD")))
                TextField("Payment amount", value: $amount, format: .currency(code: "USD")).keyboardType(.decimalPad)
                Picker("Method", selection: $method) { Text("Card / Apple Pay").tag("CARD"); Text("Cash").tag("CASH"); Text("Check").tag("CHECK") }
                if let error { Text(error).foregroundStyle(.red) }
                Button(method == "CARD" ? "Continue to payment" : "Record payment") { Task { await collect() } }
                    .disabled(loading || amount <= 0 || amount > balance)
            }.navigationTitle("Collect payment").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { await refresh() }
            .sheet(isPresented: Binding(get: {checkoutURL != nil}, set: {if !$0 {checkoutURL = nil; Task { await refresh(); await onUpdated() }}})) {
                if let url = checkoutURL { SafariView(url: url) }
            }
        }
    }
    private func refresh() async {
        loading = true; defer {loading = false}
        do {
            struct Response: Decodable {let balanceDue: Double}
            let response: Response = try await env.apiClient.post(path: "/api/estimates/\(estimateId)/payments", body: ["action":"prepare"])
            balance = response.balanceDue; amount = balance
        } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
    }
    private func collect() async {
        loading = true; error = nil; defer {loading = false}
        do {
            struct Body: Encodable {let method: String;let amount: Double;let idempotencyKey: String}
            struct Response: Decodable {let url: String?}
            let response: Response = try await env.apiClient.post(path: "/api/estimates/\(estimateId)/payments",body:Body(method:method,amount:amount,idempotencyKey:reference))
            if let value = response.url { checkoutURL = URL(string:value) }
            else { await onUpdated(); dismiss() }
        } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
    }
}
