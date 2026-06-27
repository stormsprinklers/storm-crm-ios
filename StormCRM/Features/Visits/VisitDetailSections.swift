import SwiftUI

// MARK: - Header & metadata

struct VisitHeaderSection: View {
    let visit: VisitDetailDTO
    let paymentSummary: VisitPaymentSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(visit.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(StormTheme.navy)

            HStack(spacing: 8) {
                StormBadge(text: visit.status, style: .accent)
                StormBadge(text: visit.division)
                if visit.isCallback == true {
                    StormBadge(text: "Callback", style: .warning)
                }
                if paymentSummary.isPaid {
                    StormBadge(text: "Paid", style: .success)
                }
            }

            Text(APIDateFormatting.displayString(from: visit.startAt))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let tags = visit.tags, !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(tags, id: \.self) { tag in
                            StormBadge(text: tag)
                        }
                    }
                }
            }
        }
    }
}

struct VisitScheduleInfoSection: View {
    let visit: VisitDetailDTO

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 10) {
                StormSectionHeader(title: "Schedule", systemImage: "calendar")
                LabeledContent("Start") {
                    Text(APIDateFormatting.displayString(from: visit.startAt))
                }
                LabeledContent("End") {
                    Text(APIDateFormatting.displayString(from: visit.endAt))
                }
                if let area = visit.serviceArea {
                    LabeledContent("Service area") {
                        NamedColorChip(person: area)
                    }
                }
                if let tech = visit.assignedUser {
                    LabeledContent("Assigned") {
                        NamedColorChip(person: tech)
                    }
                }
                if let crew = visit.crew {
                    LabeledContent("Crew") {
                        NamedColorChip(person: crew)
                    }
                }
            }
        }
    }
}

struct VisitTotalsSection: View {
    let subtotal: Double
    let discountTotal: Double
    let total: Double
    let paymentSummary: VisitPaymentSummary

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Visit total", systemImage: "dollarsign.circle")
                Text(total, format: .currency(code: "USD"))
                    .font(.title.weight(.semibold))
                    .foregroundStyle(StormTheme.navy)

                if discountTotal > 0 {
                    Text("Subtotal \(subtotal.formatted(.currency(code: "USD"))) · Discounts −\(discountTotal.formatted(.currency(code: "USD")))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if paymentSummary.isPaid, let invoice = paymentSummary.invoice {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(StormTheme.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Invoice \(invoice.invoiceNumber) paid")
                                .font(.subheadline.weight(.medium))
                            if let paidAt = invoice.paidAt {
                                Text(APIDateFormatting.displayString(from: paidAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(StormTheme.success.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let invoice = paymentSummary.invoice {
                    Text("Invoice \(invoice.invoiceNumber): \((paymentSummary.balanceDue ?? total).formatted(.currency(code: "USD"))) due")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct VisitTimeEventsSection: View {
    let events: [TimeEventDTO]

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Time log", systemImage: "clock")
                if events.isEmpty {
                    Text("No time events yet").foregroundStyle(.secondary)
                } else {
                    ForEach(events) { event in
                        HStack {
                            Text(event.type.replacingOccurrences(of: "_", with: " "))
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(APIDateFormatting.displayString(from: event.occurredAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let user = event.user {
                                    Text(user.name).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

struct VisitEstimatesSection: View {
    let estimates: [EstimateSummaryDTO]

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Estimates", systemImage: "doc.text")
                if estimates.isEmpty {
                    Text("No linked estimates").foregroundStyle(.secondary)
                } else {
                    ForEach(estimates) { estimate in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(estimate.status).font(.subheadline.weight(.medium))
                                Text(APIDateFormatting.displayString(from: estimate.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(estimate.total, format: .currency(code: "USD"))
                        }
                    }
                }
            }
        }
    }
}

struct VisitInstallPlanSection: View {
    let visit: VisitDetailDTO

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Install plan", systemImage: "hammer")
                if let hours = estimatedManHours {
                    Text("\(hours, format: .number.precision(.fractionLength(1))) estimated hours")
                        .font(.subheadline)
                }
                if let days = visit.installDurationDays {
                    Text("Install duration: \(days) day(s)")
                        .font(.subheadline)
                }
                if hasDesignSnapshot {
                    Text("Design zones and layout are attached to this visit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Design export attached to this visit.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var hasDesignSnapshot: Bool {
        visit.designExportMetadata?["designSnapshot"] != nil
    }

    private var estimatedManHours: Double? {
        if case .number(let value) = visit.designExportMetadata?["estimatedManHours"] {
            return value
        }
        if case .object(let obj) = visit.designExportMetadata,
           case .number(let value) = obj["estimatedManHours"] {
            return value
        }
        return nil
    }
}

struct VisitProfitSectionView: View {
    let profit: VisitProfitDTO?

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Profit", systemImage: "chart.line.uptrend.xyaxis")
                if let profit {
                    HStack {
                        metric("Revenue", profit.revenue)
                        Spacer()
                        metric("Net", profit.netProfit)
                        Spacer()
                        metric("Margin", profit.marginPercent, isPercent: true)
                    }
                    if let breakdown = profit.breakdown {
                        Divider()
                        ForEach(breakdown) { line in
                            HStack {
                                Text(line.label).font(.caption)
                                Spacer()
                                Text(line.amount, format: .currency(code: "USD")).font(.caption)
                            }
                        }
                    }
                } else {
                    Text("Profit data unavailable").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func metric(_ label: String, _ value: Double, isPercent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            if isPercent {
                Text("\(value, format: .number.precision(.fractionLength(1)))%")
                    .font(.subheadline.weight(.semibold))
            } else {
                Text(value, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

struct VisitCustomerHistorySection: View {
    let history: CustomerHistoryDTO?

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Customer history", systemImage: "clock.arrow.circlepath")
                if let history {
                    Text("\(history.pastVisitCount) past visit(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(history.visits.prefix(5)) { past in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(past.title).font(.subheadline)
                                Text(APIDateFormatting.displayString(from: past.startAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StormBadge(text: past.status)
                        }
                    }
                    if !history.estimatesWithoutVisit.isEmpty {
                        Text("Open estimates: \(history.estimatesWithoutVisit.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                } else {
                    Text("No history loaded").foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct VisitPropertyImagesSection: View {
    let property: PropertySummary

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 10) {
                StormSectionHeader(title: "Property", systemImage: "house")
                if let name = property.name {
                    Text(name).font(.subheadline.weight(.medium))
                }
                if let aerial = property.aerialImageUrl, let url = URL(string: aerial) {
                    Text("Aerial").font(.caption).foregroundStyle(.secondary)
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if let diagram = property.propertyDiagramUrl, let url = URL(string: diagram) {
                    Text("Diagram").font(.caption).foregroundStyle(.secondary)
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

struct DoNotServiceBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Customer is marked Do Not Service")
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Payment helpers

struct VisitPaymentSummary {
    let isPaid: Bool
    let balanceDue: Double?
    let invoice: InvoiceSummaryDTO?

    var hasBalanceDue: Bool {
        guard let balanceDue, balanceDue > 0 else { return false }
        return !isPaid
    }

    static func from(visit: VisitDetailDTO, computedTotal: Double) -> VisitPaymentSummary {
        guard let invoice = visit.invoices?.first else {
            return VisitPaymentSummary(
                isPaid: computedTotal <= 0,
                balanceDue: computedTotal > 0 ? computedTotal : nil,
                invoice: nil
            )
        }
        let payments = invoice.payments ?? []
        let amountPaid = payments.reduce(0.0) { partial, payment in
            payment.refundedAt == nil ? partial + payment.amount : partial
        }
        let effectiveTotal = max(invoice.total, computedTotal)
        let balanceDue = max(0, effectiveTotal - amountPaid)
        let isPaid = balanceDue <= 0
        return VisitPaymentSummary(
            isPaid: isPaid,
            balanceDue: balanceDue > 0 ? balanceDue : nil,
            invoice: invoice
        )
    }
}

func visitDiscountTotal(subtotal: Double, discounts: [DiscountDTO]) -> Double {
    discounts.reduce(0) { partial, discount in
        if discount.type.uppercased() == "PERCENT" {
            return partial + subtotal * (discount.amount / 100)
        }
        return partial + discount.amount
    }
}

func visitSubtotal(from items: [LineItemDTO]) -> Double {
    items.reduce(0) { $0 + $1.total }
}
