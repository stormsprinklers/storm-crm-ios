import MapKit
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

// MARK: - Visit layout sections

struct VisitStreetViewHeader: View {
    @EnvironmentObject private var env: AppEnvironment
    let addressQuery: String?

    @State private var streetEmbedURL: URL?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let streetEmbedURL {
                GoogleMapsEmbedWebView(url: streetEmbedURL)
            } else if isLoading {
                ZStack {
                    StormTheme.navy.opacity(0.15)
                    ProgressView()
                        .tint(.white)
                }
            } else {
                ZStack {
                    LinearGradient(
                        colors: [StormTheme.navy, StormTheme.sky.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "house.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .clipped()
        .task(id: addressQuery) { await load() }
    }

    private func load() async {
        guard let addressQuery, !addressQuery.isEmpty else {
            streetEmbedURL = nil
            return
        }
        isLoading = streetEmbedURL == nil
        defer { isLoading = false }
        do {
            let embeds: MapsEmbedResponse = try await env.apiClient.get(
                path: APIPath.mapsEmbed,
                query: [URLQueryItem(name: "q", value: addressQuery)]
            )
            if let street = embeds.streetEmbed {
                streetEmbedURL = URL(string: street)
            } else {
                streetEmbedURL = nil
            }
        } catch {
            streetEmbedURL = nil
        }
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
    let checklists: [ChecklistDTO]
    let onSaveItem: (String, String, JSONValue) async -> Void
    let onComplete: (String) async -> Void

    @State private var showChecklist = false

    private var primaryChecklist: ChecklistDTO? {
        checklists.first
    }

    private var statusLabel: String {
        guard let checklist = primaryChecklist else {
            return "No checklist selected"
        }
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
                StormSectionHeader(title: "Checklist", systemImage: "checklist")

                Text(statusLabel)
                    .font(.subheadline)
                    .foregroundStyle(primaryChecklist == nil ? .secondary : StormTheme.navy)

                if primaryChecklist != nil {
                    Button("Open checklist") {
                        showChecklist = true
                    }
                    .buttonStyle(StormPrimaryButtonStyle())
                } else {
                    Text("Add line items that match a checklist template, or assign one from the office.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    @State private var showSmsCompose = false
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
                            Button { showSmsCompose = true } label: {
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

                if let address = formattedAddress(visit) {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let url = mapsURL(address) {
                        Link("Open in Maps", destination: url)
                            .font(.subheadline)
                            .foregroundStyle(StormTheme.sky)
                    }
                }

                VisitPropertyMapPreview(
                    title: visit.title,
                    address: formattedAddress(visit),
                    latitude: visit.property?.latitude,
                    longitude: visit.property?.longitude
                )

                if let customerId = visit.customer?.id, let property = visit.property {
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
        .sheet(isPresented: $showSmsCompose) {
            if let customer = visit.customer {
                NavigationStack {
                    NewSmsConversationView(
                        scope: .customers,
                        initialContact: InboxContactDTO(
                            id: customer.id,
                            name: customer.name,
                            phone: customer.phone,
                            email: customer.email
                        )
                    ) { _ in
                        showSmsCompose = false
                    }
                }
            }
        }
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

    private func formattedAddress(_ visit: VisitDetailDTO) -> String? {
        let parts = [visit.address, visit.city, visit.state, visit.zip].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: ", ") }
        if let property = visit.property {
            let p = [property.address, property.city, property.state, property.zip].compactMap { $0 }.filter { !$0.isEmpty }
            return p.isEmpty ? nil : p.joined(separator: ", ")
        }
        return nil
    }

    private func mapsURL(_ address: String) -> URL? {
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? address
        return URL(string: "http://maps.apple.com/?q=\(encoded)")
    }
}

struct VisitPropertyMapPreview: View {
    let title: String
    let address: String?
    let latitude: Double?
    let longitude: Double?

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Property map")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let coordinate = coordinate {
                Map(position: $position) {
                    Marker(title, coordinate: coordinate)
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onAppear {
                    position = .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                    ))
                }
            } else if let address, !address.isEmpty {
                Text(address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No map location on file")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

struct VisitTagsSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let visitId: String
    let tags: [String]
    let canEdit: Bool
    var onUpdated: () async -> Void

    @State private var newTag = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 10) {
                StormSectionHeader(title: "Tags", systemImage: "tag")

                if tags.isEmpty {
                    Text(canEdit ? "No tags yet." : "No tags.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayoutTags(tags: tags, canEdit: canEdit) { tag in
                        Task { await saveTags(tags.filter { $0 != tag }) }
                    }
                }

                if canEdit {
                    HStack {
                        TextField("Add tag…", text: $newTag)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            Task { await addTag() }
                        }
                        .buttonStyle(StormSecondaryButtonStyle())
                        .disabled(isSaving || newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func addTag() async {
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !tags.contains(tag) else {
            newTag = ""
            return
        }
        newTag = ""
        await saveTags(tags + [tag])
    }

    private func saveTags(_ nextTags: [String]) async {
        isSaving = true
        error = nil
        defer { isSaving = false }

        struct Body: Encodable { let tags: [String] }
        do {
            let _: VisitDetailDTO = try await env.apiClient.patch(
                path: APIPath.visit(visitId),
                body: Body(tags: nextTags)
            )
            await onUpdated()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

private struct FlowLayoutTags: View {
    let tags: [String]
    let canEdit: Bool
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.caption.weight(.medium))
                        if canEdit {
                            Button {
                                onRemove(tag)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(StormTheme.ice.opacity(0.6))
                    .foregroundStyle(StormTheme.navy)
                    .clipShape(Capsule())
                }
            }
        }
    }
}
