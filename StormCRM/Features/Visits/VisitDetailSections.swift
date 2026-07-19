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
                StormBadge(text: visit.status.visitDisplayLabel, style: .accent)
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

struct VisitCustomerHistoryContent: View {
    let history: CustomerHistoryDTO?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let history {
                Text("\(history.pastVisitCount) past visit(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(history.visits.prefix(5)) { past in
                    NavigationLink(value: CustomerHistoryDestination.visit(past.id)) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(past.title)
                                    .font(.subheadline)
                                    .foregroundStyle(StormTheme.navy)
                                Text(APIDateFormatting.displayString(from: past.startAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StormBadge(text: past.status.visitDisplayLabel)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if !history.estimatesWithoutVisit.isEmpty {
                    Text("Open estimates: \(history.estimatesWithoutVisit.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(history.estimatesWithoutVisit.prefix(3)) { estimate in
                        NavigationLink(value: CustomerHistoryDestination.estimate(estimate.id)) {
                            HStack {
                                Text(estimate.status.replacingOccurrences(of: "_", with: " "))
                                    .font(.caption)
                                    .foregroundStyle(StormTheme.navy)
                                Spacer()
                                Text(estimate.total, format: .currency(code: "USD"))
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let invoices = history.invoices, !invoices.isEmpty {
                    Text("Invoices: \(invoices.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(invoices.prefix(3)) { invoice in
                        NavigationLink(value: CustomerHistoryDestination.invoice(invoice.id)) {
                            HStack {
                                Text(invoice.invoiceNumber)
                                    .font(.caption)
                                    .foregroundStyle(StormTheme.navy)
                                Spacer()
                                Text(invoice.total, format: .currency(code: "USD"))
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("No history loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
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
        // Always bill from current line items / discounts. Invoice.total often lags after
        // adds/deletes (e.g. still $125 after the only line item was removed).
        let effectiveTotal = computedTotal
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
    items.reduce(0) { $0 + $1.displayTotal }
}

extension Double {
    /// Prefer `self` when positive; otherwise use the fallback (e.g. computed qty×price).
    func positiveOr(_ fallback: Double) -> Double {
        self > 0 ? self : fallback
    }
}

// MARK: - Visit layout sections

/// Decorative visit header. Intentionally avoids `WKWebView` — an embed here sat under the
/// action buttons and caused system gesture-gate timeouts that swallowed taps (Payment, Parts run).
struct VisitStreetViewHeader: View {
    let addressQuery: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [StormTheme.brandNavy, StormTheme.sky.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 6) {
                Image(systemName: "house.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.55))
                if let addressQuery, !addressQuery.isEmpty {
                    Text(addressQuery)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 24)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .clipped()
        .accessibilityHidden(true)
    }
}

struct VisitWorkSummarySection: View {
    @EnvironmentObject private var env: AppEnvironment
    let visitId: String
    let initialSummary: String?
    var onSaved: () async -> Void

    @State private var text = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var didLoad = false

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 10) {
                StormSectionHeader(title: "Summary of work", systemImage: "text.alignleft")

                TextField(
                    "Describe what was done on this visit…",
                    text: $text,
                    axis: .vertical
                )
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)

                HStack {
                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .buttonStyle(StormSecondaryButtonStyle())
                    .disabled(isSaving || text == (initialSummary ?? ""))
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            text = initialSummary ?? ""
            didLoad = true
        }
        .onChange(of: initialSummary) { _, newValue in
            if !isSaving {
                text = newValue ?? ""
            }
        }
    }

    private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }

        struct Body: Encodable { let workSummary: String? }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let _: VisitDetailDTO = try await env.apiClient.patch(
                path: APIPath.visit(visitId),
                body: Body(workSummary: trimmed.isEmpty ? nil : trimmed)
            )
            await onSaved()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct VisitChecklistLauncherSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let checklists: [ChecklistDTO]
    let onSaveItem: (String, String, JSONValue) async -> Void
    let onComplete: (String) async -> Void
    let onAssignTemplate: (String) async -> Void

    @State private var showChecklist = false
    @State private var showTemplatePicker = false

    private var assignedTemplateIds: Set<String> {
        Set(checklists.compactMap(\.templateId))
    }

    private var statusLabel: String {
        guard !checklists.isEmpty else {
            return "No checklist on this visit"
        }
        if checklists.count > 1 {
            let completed = checklists.filter {
                $0.completedAt != nil || $0.status == "COMPLETED"
            }.count
            return "\(checklists.count) checklists · \(completed) complete"
        }
        let checklist = checklists[0]
        if checklist.completedAt != nil || checklist.status == "COMPLETED" {
            return "\(checklist.name) · Complete"
        }
        if let progress = checklist.progress,
           let done = progress.requiredComplete,
           let total = progress.requiredTotal,
           total > 0 {
            return "\(checklist.name) · \(done)/\(total) required"
        }
        return checklist.name
    }

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    StormSectionHeader(title: "Checklist", systemImage: "checklist")
                    Spacer(minLength: 8)
                    Button {
                        showTemplatePicker = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(StormTheme.sky)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add checklist")
                }

                Text(statusLabel)
                    .font(.subheadline)
                    .foregroundStyle(checklists.isEmpty ? .secondary : StormTheme.navy)

                if checklists.isEmpty {
                    Text("Tap + to add a checklist from your templates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Open checklist") {
                        showChecklist = true
                    }
                    .buttonStyle(StormPrimaryButtonStyle())
                }
            }
        }
        .sheet(isPresented: $showTemplatePicker) {
            ChecklistTemplatePickerSheet(
                assignedTemplateIds: assignedTemplateIds,
                userRole: env.auth.user?.role
            ) { template in
                await onAssignTemplate(template.id)
            }
        }
        .sheet(isPresented: $showChecklist) {
            NavigationStack {
                ScrollView {
                    VisitChecklistsSection(
                        checklists: checklists,
                        embedded: true,
                        onSaveItem: onSaveItem,
                        onComplete: onComplete
                    )
                    .padding()
                }
                .background(StormTheme.page.ignoresSafeArea())
                .navigationTitle("Checklist")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showChecklist = false }
                    }
                }
            }
        }
    }
}

struct VisitCustomerInfoSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let visit: VisitDetailDTO
    @ObservedObject var voice: VoiceManager
    var customerHistory: CustomerHistoryDTO? = nil

    @State private var programGuide: ControllerProgramGuideDTO?
    @State private var isLoadingGuide = false

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                StormSectionHeader(title: "Customer", systemImage: "person.crop.circle")

                if let customer = visit.customer {
                    NavigationLink(value: CustomerListRoute.detail(id: customer.id)) {
                        HStack(spacing: 6) {
                            Text(customer.name)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(StormTheme.navy)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("View customer profile")

                    if let phone = customer.phone, !phone.isEmpty {
                        HStack(spacing: 16) {
                            Button {
                                env.openCustomerSmsInbox(
                                    customerId: customer.id,
                                    name: customer.name,
                                    phone: phone
                                )
                            } label: {
                                Image(systemName: "message.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(StormTheme.sky)
                            .accessibilityLabel("Message customer")

                            Button {
                                Task { await voice.call(phone: phone, customerId: customer.id) }
                            } label: {
                                Image(systemName: "phone.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(StormTheme.sky)
                            .accessibilityLabel("Call customer")

                            Text(phone)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let email = customer.email, !email.isEmpty {
                        Link(destination: URL(string: "mailto:\(email)")!) {
                            Label(email, systemImage: "envelope")
                        }
                        .font(.subheadline)
                    }
                }

                if let address = AppleMapsURL.formattedAddress(for: visit) {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let url = AppleMapsURL.directionsURL(
                        latitude: visit.property?.latitude,
                        longitude: visit.property?.longitude,
                        address: address
                    ) {
                        Link("Open in Maps", destination: url)
                            .font(.subheadline)
                            .foregroundStyle(StormTheme.sky)
                    }
                }

                if visit.customer != nil {
                    DisclosureGroup {
                        VisitCustomerHistoryContent(history: customerHistory)
                    } label: {
                        Label(historyDisclosureTitle, systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(StormTheme.navy)
                    }
                }

                if let customerId = visit.customer?.id, let property = visit.property {
                    VisitPropertyIrrigationPreview(customerId: customerId, property: property)

                    DisclosureGroup {
                        if isLoadingGuide {
                            ProgressView("Loading program guide…")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        } else if let programGuide {
                            IrrigationProgramGuideView(guide: programGuide)
                        } else {
                            Text("No program guide for this property.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Label("Programming guide", systemImage: "drop.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(StormTheme.navy)
                    }
                    .task(id: property.id) {
                        await loadProgramGuide(customerId: customerId, propertyId: property.id)
                    }
                }
            }
        }
    }

    private var historyDisclosureTitle: String {
        if let count = customerHistory?.pastVisitCount {
            return "History · \(count) past visit\(count == 1 ? "" : "s")"
        }
        return "Customer history"
    }

    private func loadProgramGuide(customerId: String, propertyId: String) async {
        isLoadingGuide = programGuide == nil
        defer { isLoadingGuide = false }
        do {
            let response: IrrigationProgramResponse = try await env.apiClient.get(
                path: APIPath.irrigationProgram(customerId: customerId, propertyId: propertyId)
            )
            programGuide = response.guide
        } catch {
            programGuide = nil
        }
    }

}


