import SafariServices
import SwiftUI

struct PaymentSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let visitId: String
    @State private var checkoutURL: URL?
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if isLoading {
                    ProgressView("Creating checkout…")
                } else if let error {
                    Text(error).foregroundStyle(.red)
                } else if let checkoutURL {
                    SafariView(url: checkoutURL)
                } else {
                    Text("Collect payment via Stripe Checkout.")
                    Button("Start checkout") {
                        Task { await startCheckout() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("Collect payment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await startCheckout() }
        }
    }

    private func startCheckout() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        struct Body: Encodable {
            let visitId: String
            let mobileReturn: Bool
            let platform: String
        }
        do {
            let response: CheckoutResponse = try await env.apiClient.post(
                path: APIPath.paymentsCheckout,
                body: Body(visitId: visitId, mobileReturn: true, platform: "ios")
            )
            if let urlString = response.url, let url = URL(string: urlString) {
                checkoutURL = url
            } else {
                error = "No checkout URL returned"
            }
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct PaymentReturnSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    let payment: PaymentReturn
    @State private var message = "Processing payment…"

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(message)
                if payment.cancelled {
                    Text("Payment cancelled").foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Payment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { env.paymentReturn = nil }
                }
            }
            .task { await confirmIfNeeded() }
        }
    }

    private func confirmIfNeeded() async {
        guard !payment.cancelled, let sessionId = payment.sessionId else {
            message = payment.cancelled ? "Cancelled" : "No session"
            return
        }
        struct Body: Encodable { let sessionId: String }
        do {
            struct ConfirmResponse: Decodable { let ok: Bool? }
            let _: ConfirmResponse = try await env.apiClient.post(
                path: APIPath.paymentsConfirm,
                body: Body(sessionId: sessionId)
            )
            message = "Payment recorded"
        } catch {
            message = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

#if canImport(UIKit)
import UIKit
#endif
