import SafariServices
import SwiftUI

struct VisitPaymentsSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let visitId: String
    let total: Double
    let hasLineItems: Bool
    let paymentSummary: VisitPaymentSummary
    var onUpdated: () async -> Void

    @State private var showPayment = false
    @State private var payLink: String?
    @State private var isSendingInvoice = false
    @State private var isPreparingLink = false
    @State private var message: String?
    @State private var error: String?

    private var amountDue: Double {
        paymentSummary.balanceDue ?? total
    }

    private var canBill: Bool {
        hasLineItems && total > 0 && paymentSummary.hasBalanceDue
    }

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                StormSectionHeader(title: "Payment", systemImage: "creditcard")

                if paymentSummary.isPaid {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(StormTheme.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Paid in full")
                                .font(.subheadline.weight(.semibold))
                            if let invoice = paymentSummary.invoice {
                                Text("Invoice \(invoice.invoiceNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if total <= 0 {
                    Text("Add line items to bill this visit.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if !hasLineItems {
                    Text("Add at least one line item before collecting payment or sending an invoice.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(amountDue, format: .currency(code: "USD"))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(StormTheme.navy)

                    if let invoice = paymentSummary.invoice {
                        Text("Invoice \(invoice.invoiceNumber) · \(invoice.status.replacingOccurrences(of: "_", with: " "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Invoice will be created when you collect or send.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 8) {
                        Button {
                            showPayment = true
                        } label: {
                            Label("Collect payment", systemImage: "creditcard.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(StormPrimaryButtonStyle())
                        .disabled(!canBill)

                        Button {
                            Task { await sendInvoice() }
                        } label: {
                            HStack {
                                if isSendingInvoice {
                                    ProgressView().controlSize(.small)
                                }
                                Label(
                                    isSendingInvoice ? "Sending invoice…" : "Send invoice to customer",
                                    systemImage: "paperplane.fill"
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(StormSecondaryButtonStyle())
                        .disabled(!canBill || isSendingInvoice)

                        if let link = payLink, let url = URL(string: link) {
                            ShareLink(item: url) {
                                Label("Share pay link", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(StormSecondaryButtonStyle())
                        } else {
                            Button {
                                Task { await preparePayLink() }
                            } label: {
                                HStack {
                                    if isPreparingLink {
                                        ProgressView().controlSize(.small)
                                    }
                                    Label(
                                        isPreparingLink ? "Preparing link…" : "Get pay link",
                                        systemImage: "link"
                                    )
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(StormSecondaryButtonStyle())
                            .disabled(!canBill || isPreparingLink)
                        }
                    }
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(StormTheme.success)
                }
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .sheet(isPresented: $showPayment) {
            PaymentSheet(visitId: visitId, amountDue: amountDue) {
                Task { await onUpdated() }
            }
        }
    }

    private func sendInvoice() async {
        isSendingInvoice = true
        error = nil
        message = nil
        defer { isSendingInvoice = false }
        struct Body: Encodable { let send: Bool }
        do {
            let response: VisitInvoiceResponse = try await env.apiClient.post(
                path: APIPath.visitInvoice(visitId),
                body: Body(send: true)
            )
            payLink = response.payLink
            var parts: [String] = ["Invoice sent"]
            if response.emailSent == true { parts.append("email") }
            if response.smsSent == true { parts.append("SMS") }
            if parts.count > 1 {
                message = "Invoice sent via \(parts.dropFirst().joined(separator: " and "))."
            } else {
                message = "Invoice sent to customer."
            }
            await onUpdated()
        } catch let apiError as APIError {
            if case .server(let msg) = apiError, msg.contains("pay link") {
                error = msg
                await preparePayLink()
            } else {
                self.error = apiError.message
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func preparePayLink() async {
        isPreparingLink = true
        error = nil
        defer { isPreparingLink = false }
        struct Body: Encodable { let send: Bool }
        do {
            let response: VisitInvoiceResponse = try await env.apiClient.post(
                path: APIPath.visitInvoice(visitId),
                body: Body(send: false)
            )
            payLink = response.payLink
            message = "Pay link ready — share it with the customer."
            await onUpdated()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct PaymentSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let visitId: String
    let amountDue: Double
    var onCompleted: () -> Void

    @State private var checkoutURL: URL?
    @State private var payLink: String?
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if isLoading {
                    ProgressView("Starting secure checkout…")
                } else if let error {
                    Text(error).foregroundStyle(.red).multilineTextAlignment(.center)
                    Button("Try again") { Task { await startCheckout() } }
                        .buttonStyle(StormPrimaryButtonStyle())
                } else if let checkoutURL {
                    Text("Complete payment in the browser. You'll return here when finished.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    SafariView(url: checkoutURL)
                } else {
                    Text(amountDue, format: .currency(code: "USD"))
                        .font(.title.weight(.bold))
                    Text("Collect payment with card via Stripe Checkout.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Start checkout") {
                        Task { await startCheckout() }
                    }
                    .buttonStyle(StormPrimaryButtonStyle())
                }

                if let payLink, let url = URL(string: payLink) {
                    ShareLink(item: url) {
                        Label("Share pay link instead", systemImage: "square.and.arrow.up")
                    }
                    .font(.subheadline)
                }
            }
            .padding()
            .navigationTitle("Collect payment")
            .navigationBarTitleDisplayMode(.inline)
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
            payLink = response.payLink
            if let urlString = response.url, let url = URL(string: urlString) {
                checkoutURL = url
            } else {
                error = "No checkout URL returned. Check that Stripe is configured on the server."
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
    @State private var succeeded = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if succeeded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(StormTheme.success)
                }
                Text(message)
                    .multilineTextAlignment(.center)
                if payment.cancelled {
                    Text("Payment cancelled").foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Payment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        env.paymentReturn = nil
                    }
                }
            }
            .task { await confirmIfNeeded() }
        }
    }

    private func confirmIfNeeded() async {
        guard !payment.cancelled, let sessionId = payment.sessionId else {
            message = payment.cancelled ? "Payment cancelled" : "No payment session"
            return
        }

        struct Body: Encodable { let sessionId: String }
        for attempt in 0..<8 {
            do {
                let response: PaymentConfirmResponse = try await env.apiClient.post(
                    path: APIPath.paymentsConfirm,
                    body: Body(sessionId: sessionId)
                )
                if response.confirmed == true {
                    message = "Payment recorded"
                    succeeded = true
                    NotificationCenter.default.post(
                        name: .visitPaymentCompleted,
                        object: nil,
                        userInfo: ["visitId": payment.visitId]
                    )
                    return
                }
                if response.reason == "payment_pending", attempt < 7 {
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                    continue
                }
                message = "Payment is still processing. Pull to refresh the visit in a moment."
                return
            } catch {
                if attempt == 7 {
                    message = (error as? APIError)?.message ?? error.localizedDescription
                } else {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
            }
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

extension Notification.Name {
    static let visitPaymentCompleted = Notification.Name("stormcrm.visitPaymentCompleted")
}

#if canImport(UIKit)
import UIKit
#endif
