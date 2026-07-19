import CoreImage.CIFilterBuiltins
import SafariServices
import SwiftUI
import UIKit

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
                        if !env.offlineSync.isOnline {
                            Text("Offline — cash/check and send-link can be saved securely and sync when you're back online. Card and QR need a connection.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if env.offlineSync.hasPendingPayment(forVisitId: visitId) {
                            let label = env.offlineSync.pendingPaymentMethodLabel(forVisitId: visitId) ?? "Payment"
                            Text("\(label) recorded on device — waiting to sync.")
                                .font(.caption)
                                .foregroundStyle(StormTheme.sky)
                        }
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

                        if payLink != nil {
                            // Resend via CRM email/SMS — not the system share sheet.
                            Button {
                                Task { await sendInvoice() }
                            } label: {
                                HStack {
                                    if isSendingInvoice {
                                        ProgressView().controlSize(.small)
                                    }
                                    Label(
                                        isSendingInvoice ? "Sending…" : "Text or email pay link",
                                        systemImage: "paperplane.fill"
                                    )
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(StormSecondaryButtonStyle())
                            .disabled(!canBill || isSendingInvoice)
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
                            .disabled(!canBill || isPreparingLink || !env.offlineSync.isOnline)
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

private enum PaymentCollectMethod: String, CaseIterable, Identifiable {
    case manualCard
    case qrCode
    case sendLink
    case cashCheck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manualCard: return "Manual card"
        case .qrCode: return "QR code"
        case .sendLink: return "Send payment link"
        case .cashCheck: return "Cash / Check"
        }
    }

    var subtitle: String {
        switch self {
        case .manualCard: return "Open secure checkout on this device"
        case .qrCode: return "Customer scans to open the payment link"
        case .sendLink: return "Email / text the pay link to the customer"
        case .cashCheck: return "Record cash or check and notify admins"
        }
    }

    var requiresOnline: Bool {
        switch self {
        case .manualCard, .qrCode: return true
        case .sendLink, .cashCheck: return false
        }
    }

    var systemImage: String {
        switch self {
        case .manualCard: return "creditcard.fill"
        case .qrCode: return "qrcode"
        case .sendLink: return "paperplane.fill"
        case .cashCheck: return "banknote.fill"
        }
    }
}

struct PaymentSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let visitId: String
    let amountDue: Double
    var onCompleted: () -> Void

    @State private var selectedMethod: PaymentCollectMethod?
    @State private var checkoutURL: URL?
    @State private var payLink: String?
    @State private var error: String?
    @State private var statusMessage: String?
    @State private var isLoading = false
    @State private var showCashCheckConfirm = false
    @State private var cashCheckKind: String = "CASH"

    var body: some View {
        NavigationStack {
            Group {
                if let selectedMethod {
                    methodDetail(selectedMethod)
                } else {
                    methodPicker
                }
            }
            .padding()
            .navigationTitle("Collect payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selectedMethod == nil ? "Close" : "Back") {
                        if selectedMethod == nil {
                            dismiss()
                        } else {
                            selectedMethod = nil
                            error = nil
                            statusMessage = nil
                            checkoutURL = nil
                            payLink = nil
                        }
                    }
                }
            }
            .confirmationDialog(
                "Record cash or check?",
                isPresented: $showCashCheckConfirm,
                titleVisibility: .visible
            ) {
                Button("Cash \(amountDue.formatted(.currency(code: "USD")))") {
                    cashCheckKind = "CASH"
                    Task { await recordManualPayment(method: "CASH") }
                }
                Button("Check \(amountDue.formatted(.currency(code: "USD")))") {
                    cashCheckKind = "CHECK"
                    Task { await recordManualPayment(method: "CHECK") }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    env.offlineSync.isOnline
                        ? "Admins will be notified that this job was collected with cash or check."
                        : "Saved encrypted on this device. It will sync and notify admins when you're back online."
                )
            }
        }
    }

    private var methodPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(amountDue, format: .currency(code: "USD"))
                .font(.title.weight(.bold))
                .foregroundStyle(StormTheme.navy)

            Text("How do you want to collect?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !env.offlineSync.isOnline {
                Text("You're offline. Cash/check and send-link are saved encrypted on this device and sync when signal returns.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ForEach(PaymentCollectMethod.allCases) { method in
                let needsNet = method.requiresOnline && !env.offlineSync.isOnline
                Button {
                    selectMethod(method)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: method.systemImage)
                            .font(.title3)
                            .foregroundStyle(needsNet ? Color.secondary : StormTheme.sky)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(method.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(needsNet ? Color.secondary : StormTheme.navy)
                            Text(needsNet ? "Needs an internet connection" : method.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(StormTheme.ice.opacity(needsNet ? 0.25 : 0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isLoading || needsNet)
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func methodDetail(_ method: PaymentCollectMethod) -> some View {
        VStack(spacing: 16) {
            // Keep an already-built QR visible while text/email send is in flight.
            if isLoading, !(method == .qrCode && payLink != nil) {
                ProgressView(loadingLabel(for: method))
            } else if let error, !(method == .qrCode && payLink != nil) {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Try again") { selectMethod(method) }
                    .buttonStyle(StormPrimaryButtonStyle())
            } else {
                switch method {
                case .manualCard:
                    if let checkoutURL {
                        Text("Complete card payment below. You'll return here when finished.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        SafariView(url: checkoutURL)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .qrCode:
                    if let payLink {
                        Text("Have the customer scan this code to pay.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if let image = QRCodeImage.make(from: payLink) {
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 260)
                                .padding()
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Text(payLink)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                        if let error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                        if let statusMessage {
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(StormTheme.success)
                                .multilineTextAlignment(.center)
                        }
                        // Send via CRM email/SMS — not the system share sheet.
                        Button {
                            Task { await sendPaymentLink(fromQR: true) }
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView().controlSize(.small)
                                }
                                Label(
                                    isLoading ? "Sending…" : "Text or email link",
                                    systemImage: "paperplane.fill"
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(StormSecondaryButtonStyle())
                        .disabled(isLoading)
                    } else if isLoading {
                        ProgressView(loadingLabel(for: method))
                    }
                case .sendLink:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(StormTheme.success)
                    Text(statusMessage ?? "Payment link sent.")
                        .multilineTextAlignment(.center)
                    Button("Done") {
                        onCompleted()
                        dismiss()
                    }
                    .buttonStyle(StormPrimaryButtonStyle())
                case .cashCheck:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(StormTheme.success)
                    Text(statusMessage ?? "\(cashCheckKind.capitalized) payment recorded. Admins notified.")
                        .multilineTextAlignment(.center)
                    Button("Done") {
                        onCompleted()
                        dismiss()
                    }
                    .buttonStyle(StormPrimaryButtonStyle())
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func loadingLabel(for method: PaymentCollectMethod) -> String {
        switch method {
        case .manualCard: return "Starting card checkout…"
        case .qrCode: return "Preparing QR code…"
        case .sendLink: return "Sending payment link…"
        case .cashCheck: return "Recording payment…"
        }
    }

    private func selectMethod(_ method: PaymentCollectMethod) {
        error = nil
        statusMessage = nil
        checkoutURL = nil
        if method.requiresOnline, !env.offlineSync.isOnline {
            error = "This payment method needs an internet connection."
            return
        }
        switch method {
        case .manualCard:
            selectedMethod = method
            Task { await startCheckout() }
        case .qrCode:
            selectedMethod = method
            Task { await preparePayLink() }
        case .sendLink:
            selectedMethod = method
            Task { await sendPaymentLink() }
        case .cashCheck:
            showCashCheckConfirm = true
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
            payLink = response.url ?? response.payLink
            if let urlString = response.url ?? response.payLink, let url = URL(string: urlString) {
                checkoutURL = url
            } else {
                error = "No checkout URL returned. Check that card payments are configured on the server."
            }
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func preparePayLink() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        struct Body: Encodable {
            let visitId: String
            let mobileReturn: Bool
            let platform: String
        }
        do {
            // Prefer Stripe Checkout session.url (Apple Pay / Klarna / branded domain when ready).
            let response: CheckoutResponse = try await env.apiClient.post(
                path: APIPath.paymentsCheckout,
                body: Body(visitId: visitId, mobileReturn: true, platform: "ios")
            )
            payLink = response.url ?? response.payLink
            if payLink == nil {
                error = "Could not create a payment link."
            }
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func sendPaymentLink(fromQR: Bool = false) async {
        isLoading = true
        error = nil
        statusMessage = nil
        defer { isLoading = false }
        struct Body: Encodable { let send: Bool }
        let body = Body(send: true)

        if !env.offlineSync.isOnline {
            queueSendLink(fromQR: fromQR)
            return
        }

        do {
            let response: VisitInvoiceResponse = try await env.apiClient.post(
                path: APIPath.visitInvoice(visitId),
                body: body
            )
            if let link = response.payLink {
                payLink = link
            }
            var parts: [String] = []
            if response.emailSent == true { parts.append("email") }
            if response.smsSent == true { parts.append("SMS") }
            if parts.isEmpty {
                statusMessage = "Payment link prepared\(response.payLink.map { ": \($0)" } ?? ".")"
            } else {
                statusMessage = "Payment link sent via \(parts.joined(separator: " and "))."
            }
            onCompleted()
            // From the dedicated send-link method, show the success screen.
            // From QR, stay on the QR view so the code remains usable.
            if !fromQR {
                selectedMethod = .sendLink
            }
        } catch {
            if isLikelyOffline(error) {
                queueSendLink(fromQR: fromQR)
            } else {
                self.error = (error as? APIError)?.message ?? error.localizedDescription
            }
        }
    }

    private func queueSendLink(fromQR: Bool = false) {
        struct SendBody: Encodable { let send: Bool }
        guard let payload = try? JSONCoding.makeEncoder().encode(SendBody(send: true)) else {
            error = "Could not save payment link request offline."
            return
        }
        env.offlineSync.enqueue(
            path: APIPath.visitInvoice(visitId),
            method: "POST",
            bodyData: payload,
            secure: true,
            relatedVisitId: visitId
        )
        statusMessage = "Payment link request saved offline — it will send when you're back online."
        onCompleted()
        if !fromQR {
            selectedMethod = .sendLink
        }
    }

    private func recordManualPayment(method: String) async {
        selectedMethod = .cashCheck
        isLoading = true
        error = nil
        defer { isLoading = false }

        struct Body: Encodable {
            let visitId: String
            let method: String
            let amount: Double
            let idempotencyKey: String
        }
        let key = UUID().uuidString
        let body = Body(
            visitId: visitId,
            method: method,
            amount: amountDue,
            idempotencyKey: key
        )

        if !env.offlineSync.isOnline {
            queueManualPayment(body: body, method: method, idempotencyKey: key)
            return
        }

        do {
            let _: ManualPaymentResponse = try await env.apiClient.post(
                path: APIPath.paymentsManual,
                body: body,
                headers: ["Idempotency-Key": key]
            )
            cashCheckKind = method
            statusMessage = "\(method == "CASH" ? "Cash" : "Check") payment recorded. Admins have been notified."
            onCompleted()
        } catch {
            if isLikelyOffline(error) {
                queueManualPayment(body: body, method: method, idempotencyKey: key)
            } else {
                self.error = (error as? APIError)?.message ?? error.localizedDescription
            }
        }
    }

    private func queueManualPayment(body: some Encodable, method: String, idempotencyKey: String) {
        guard let payload = try? JSONCoding.makeEncoder().encode(body) else {
            error = "Could not save payment offline."
            return
        }
        env.offlineSync.enqueue(
            path: APIPath.paymentsManual,
            method: "POST",
            bodyData: payload,
            secure: true,
            relatedVisitId: visitId,
            idempotencyKey: idempotencyKey
        )
        cashCheckKind = method
        statusMessage =
            "\(method == "CASH" ? "Cash" : "Check") payment saved securely on this device. It will sync and notify admins when you're back online."
        onCompleted()
    }

    private func isLikelyOffline(_ error: Error) -> Bool {
        if let apiError = error as? APIError, case .network = apiError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && (
            nsError.code == NSURLErrorNotConnectedToInternet
                || nsError.code == NSURLErrorNetworkConnectionLost
                || nsError.code == NSURLErrorTimedOut
        )
    }
}

private struct ManualPaymentResponse: Decodable {
    let ok: Bool?
    let invoiceStatus: String?
    let amount: Double?
    let method: String?
}

enum QRCodeImage {
    /// Brand coral modules on white — matches app accents while staying scannable.
    static func make(from string: String, tint: UIColor = UIColor(StormTheme.coral)) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let colored = scaled.applyingFilter(
            "CIFalseColor",
            parameters: [
                "inputColor0": CIColor(color: tint),
                "inputColor1": CIColor(color: .white),
            ]
        )
        guard let cgImage = context.createCGImage(colored, from: colored.extent) else { return nil }
        return UIImage(cgImage: cgImage)
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
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredControlTintColor = UIColor(StormTheme.coral)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

extension Notification.Name {
    static let visitPaymentCompleted = Notification.Name("stormcrm.visitPaymentCompleted")
}
