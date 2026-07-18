import SwiftUI

struct InvoiceDetailDTO: Decodable, Identifiable {
    let id: String
    let invoiceNumber: String
    let status: String
    let subtotal: Double
    let discountTotal: Double
    let tax: Double
    let total: Double
    let paidAt: String?
    let sentAt: String?
    let createdAt: String
    let customer: InvoiceCustomerDTO
    let visit: InvoiceVisitRefDTO?
    let lineItems: [LineItemDTO]
    let payments: [InvoicePaymentDetailDTO]
    let amountPaid: Double
    let balanceDue: Double

    enum CodingKeys: String, CodingKey {
        case id, invoiceNumber, status, subtotal, discountTotal, tax, total
        case paidAt, sentAt, createdAt, customer, visit, lineItems, payments
        case amountPaid, balanceDue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        invoiceNumber = try container.decode(String.self, forKey: .invoiceNumber)
        status = try container.decode(String.self, forKey: .status)
        subtotal = try container.decodeFlexibleDouble(forKey: .subtotal) ?? 0
        discountTotal = try container.decodeFlexibleDouble(forKey: .discountTotal) ?? 0
        tax = try container.decodeFlexibleDouble(forKey: .tax) ?? 0
        total = try container.decodeFlexibleDouble(forKey: .total) ?? 0
        paidAt = try container.decodeIfPresent(String.self, forKey: .paidAt)
        sentAt = try container.decodeIfPresent(String.self, forKey: .sentAt)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        customer = try container.decode(InvoiceCustomerDTO.self, forKey: .customer)
        visit = try container.decodeIfPresent(InvoiceVisitRefDTO.self, forKey: .visit)
        lineItems = try container.decodeIfPresent([LineItemDTO].self, forKey: .lineItems) ?? []
        payments = try container.decodeIfPresent([InvoicePaymentDetailDTO].self, forKey: .payments) ?? []
        amountPaid = try container.decodeFlexibleDouble(forKey: .amountPaid) ?? 0
        balanceDue = try container.decodeFlexibleDouble(forKey: .balanceDue) ?? 0
    }
}

struct InvoiceCustomerDTO: Decodable {
    let id: String
    let name: String
    let phone: String?
    let email: String?
}

struct InvoiceVisitRefDTO: Decodable {
    let id: String
    let title: String
}

struct InvoicePaymentDetailDTO: Decodable, Identifiable {
    let id: String
    let amount: Double
    let method: String
    let paidAt: String
    let refundedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, amount, method, paidAt, refundedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        amount = try container.decodeFlexibleDouble(forKey: .amount) ?? 0
        method = try container.decode(String.self, forKey: .method)
        paidAt = try container.decode(String.self, forKey: .paidAt)
        refundedAt = try container.decodeIfPresent(String.self, forKey: .refundedAt)
    }
}

struct InvoiceDetailView: View {
    @EnvironmentObject private var env: AppEnvironment

    let invoiceId: String

    @State private var invoice: InvoiceDetailDTO?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && invoice == nil {
                ProgressView("Loading invoice…")
            } else if let invoice {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        StormCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(invoice.invoiceNumber)
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(StormTheme.navy)
                                    Spacer()
                                    StormBadge(text: invoice.status.replacingOccurrences(of: "_", with: " "))
                                }
                                Text(invoice.customer.name)
                                    .font(.subheadline.weight(.medium))
                                Text("Created \(APIDateFormatting.displayString(from: invoice.createdAt))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let paidAt = invoice.paidAt {
                                    Text("Paid \(APIDateFormatting.displayString(from: paidAt))")
                                        .font(.caption)
                                        .foregroundStyle(StormTheme.success)
                                }
                            }
                        }

                        if let visit = invoice.visit {
                            StormCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    StormSectionHeader(title: "Linked visit", systemImage: "wrench.and.screwdriver")
                                    NavigationLink(value: CustomerHistoryDestination.visit(visit.id)) {
                                        HStack {
                                            Text(visit.title)
                                                .font(.subheadline)
                                                .foregroundStyle(StormTheme.navy)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        StormCard {
                            VStack(alignment: .leading, spacing: 8) {
                                StormSectionHeader(title: "Line items", systemImage: "list.bullet")
                                ForEach(invoice.lineItems) { item in
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name).font(.subheadline.weight(.medium))
                                            if let description = item.description, !description.isEmpty {
                                                Text(description)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Text(item.total, format: .currency(code: "USD"))
                                            .font(.subheadline)
                                    }
                                    if item.id != invoice.lineItems.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }

                        StormCard {
                            VStack(alignment: .leading, spacing: 6) {
                                summaryRow("Subtotal", invoice.subtotal)
                                if invoice.discountTotal > 0 {
                                    summaryRow("Discounts", -invoice.discountTotal)
                                }
                                if invoice.tax > 0 {
                                    summaryRow("Tax", invoice.tax)
                                }
                                Divider()
                                summaryRow("Total", invoice.total, bold: true)
                                summaryRow("Paid", invoice.amountPaid)
                                summaryRow("Balance due", invoice.balanceDue, bold: true)
                            }
                            .font(.subheadline)
                        }

                        if !invoice.payments.isEmpty {
                            StormCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    StormSectionHeader(title: "Payments", systemImage: "creditcard")
                                    ForEach(invoice.payments) { payment in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(payment.method.replacingOccurrences(of: "_", with: " "))
                                                    .font(.subheadline)
                                                Text(APIDateFormatting.displayString(from: payment.paidAt))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text(payment.amount, format: .currency(code: "USD"))
                                                .font(.subheadline.weight(.medium))
                                        }
                                        if payment.id != invoice.payments.last?.id {
                                            Divider()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Invoice unavailable",
                    systemImage: "doc.plaintext",
                    description: Text(error ?? "Could not load invoice")
                )
            }
        }
        .background(StormTheme.page.ignoresSafeArea())
        .navigationTitle("Invoice")
        .navigationBarTitleDisplayMode(.inline)

        .refreshable { await load() }
        .task { await load() }
    }

    private func summaryRow(_ label: String, _ value: Double, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(bold ? .primary : .secondary)
                .fontWeight(bold ? .semibold : .regular)
            Spacer()
            Text(value, format: .currency(code: "USD"))
                .fontWeight(bold ? .semibold : .regular)
        }
    }

    private func load() async {
        isLoading = invoice == nil
        error = nil
        defer { isLoading = false }
        do {
            invoice = try await env.apiClient.get(path: APIPath.invoice(invoiceId))
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
