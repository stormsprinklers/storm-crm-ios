import SwiftUI

struct VisitEstimatesSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let visit: VisitDetailDTO
    let visitId: String
    var onUpdated: () async -> Void

    @State private var isCreating = false
    @State private var error: String?
    @State private var navigateToEstimateId: String?

    private var estimates: [EstimateSummaryDTO] {
        visit.estimates ?? []
    }

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    StormSectionHeader(title: "Estimates", systemImage: "doc.text")
                    Spacer()
                    Button {
                        Task { await createEstimate() }
                    } label: {
                        if isCreating {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("New estimate", systemImage: "plus")
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(StormSecondaryButtonStyle())
                    .disabled(isCreating || visit.customer == nil)
                }

                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                if estimates.isEmpty {
                    Text("No estimates linked to this visit yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(estimates) { estimate in
                        NavigationLink {
                            EstimateDetailView(
                                estimateId: estimate.id,
                                sourceVisit: visit,
                                sourceVisitId: visitId
                            ) {
                                await onUpdated()
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(estimate.titleLabel)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(StormTheme.navy)
                                    HStack(spacing: 6) {
                                        Text(estimate.total, format: .currency(code: "USD"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        StormBadge(text: estimate.status)
                                        Text(APIDateFormatting.displayString(from: estimate.createdAt))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        if estimate.id != estimates.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { navigateToEstimateId != nil },
            set: { if !$0 { navigateToEstimateId = nil } }
        )) {
            if let estimateId = navigateToEstimateId {
                EstimateDetailView(
                    estimateId: estimateId,
                    sourceVisit: visit,
                    sourceVisitId: visitId
                ) {
                    await onUpdated()
                }
            }
        }
    }

    private func createEstimate() async {
        guard let customerId = visit.customer?.id else {
            error = "Visit must have a customer"
            return
        }
        isCreating = true
        error = nil
        defer { isCreating = false }
        do {
            let body = CreateEstimateBody(
                customerId: customerId,
                propertyId: visit.property?.id,
                visitId: visitId
            )
            let created: EstimateDetailDTO = try await env.apiClient.post(
                path: APIPath.estimates,
                body: body
            )
            await onUpdated()
            navigateToEstimateId = created.id
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct EstimateDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let estimateId: String
    var sourceVisit: VisitDetailDTO?
    var sourceVisitId: String?
    var onUpdated: () async -> Void

    init(
        estimateId: String,
        sourceVisit: VisitDetailDTO? = nil,
        sourceVisitId: String? = nil,
        onUpdated: @escaping () async -> Void = {}
    ) {
        self.estimateId = estimateId
        self.sourceVisit = sourceVisit
        self.sourceVisitId = sourceVisitId
        self.onUpdated = onUpdated
    }

    @State private var estimate: EstimateDetailDTO?
    @State private var customerHistory: CustomerHistoryDTO?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var error: String?
    @State private var actionMessage: String?
    @State private var showCopyNewVisitConfirm = false
    @State private var hasSignatureInk = false
    @StateObject private var signatureController = EstimateSignatureController()

    var body: some View {
        Group {
            if isLoading && estimate == nil {
                ProgressView("Loading estimate…")
            } else if let estimate {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(for: estimate)

                        EstimateCustomerInfoSection(
                            customer: estimate.customer,
                            property: estimate.property,
                            voice: env.voice,
                            customerHistory: customerHistory
                        )

                        if let actionMessage {
                            Text(actionMessage)
                                .font(.footnote)
                                .foregroundStyle(StormTheme.success)
                        }
                        if let error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }

                        LineItemsSummarySection(
                            owner: .estimate(
                                id: estimateId,
                                optionId: estimate.selectedOptionId ?? estimate.options.first?.id
                            ),
                            items: {
                                let optionId = estimate.selectedOptionId ?? estimate.options.first?.id
                                if let optionId {
                                    return estimate.lineItems.filter {
                                        $0.optionId == optionId || $0.optionId == nil
                                    }
                                }
                                return estimate.lineItems
                            }(),
                            discounts: estimate.discounts,
                            subtotal: estimate.subtotal,
                            discountTotal: estimate.discountTotal,
                            total: estimate.total,
                            canEdit: estimate.status != "CONVERTED"
                        ) {
                            await load()
                            await onUpdated()
                        }
                        actionsSection(for: estimate)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Estimate unavailable",
                    systemImage: "doc.text",
                    description: Text(error ?? "Could not load estimate")
                )
            }
        }
        .background(StormTheme.page.ignoresSafeArea())
        .navigationTitle(estimate?.displayTitle ?? "Estimate")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(
            "Schedule a new visit with these line items?",
            isPresented: $showCopyNewVisitConfirm,
            titleVisibility: .visible
        ) {
            Button("Create new visit") {
                Task { await copyToVisit(target: "new_visit") }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A new scheduled visit will be created and this estimate's line items will be copied to it.")
        }
    }

    @ViewBuilder
    private func header(for estimate: EstimateDetailDTO) -> some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(estimate.displayTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(StormTheme.navy)
                    Spacer()
                    StormBadge(text: estimate.status)
                }
                Text(estimate.total, format: .currency(code: "USD"))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(StormTheme.navy)
                if estimate.options.count > 1 {
                    Text("\(estimate.options.count) options")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let expiresAt = estimate.expiresAt {
                    Text("Expires \(APIDateFormatting.displayString(from: expiresAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if estimate.signedAt != nil {
                    Text("Customer signed")
                        .font(.caption)
                        .foregroundStyle(StormTheme.success)
                }
            }
        }
    }

    @ViewBuilder
    private func totalsSection(for estimate: EstimateDetailDTO) -> some View {
        StormCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Subtotal")
                    Spacer()
                    Text(estimate.subtotal, format: .currency(code: "USD"))
                }
                if estimate.discountTotal > 0 {
                    HStack {
                        Text("Discounts")
                        Spacer()
                        Text(-estimate.discountTotal, format: .currency(code: "USD"))
                    }
                    .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Total").font(.headline)
                    Spacer()
                    Text(estimate.total, format: .currency(code: "USD"))
                        .font(.headline)
                }
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private func actionsSection(for estimate: EstimateDetailDTO) -> some View {
        if estimate.status == "CONVERTED" {
            StormCard {
                Text("This estimate was copied to a visit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            StormCard {
                VStack(alignment: .leading, spacing: 10) {
                    StormSectionHeader(title: "Actions", systemImage: "bolt")

                    if estimate.status == "DRAFT" || estimate.status == "SENT" {
                        Button {
                            Task { await sendEstimate() }
                        } label: {
                            Label(isSaving ? "Sending…" : "Send to customer", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(StormSecondaryButtonStyle())
                        .disabled(isSaving)
                    }

                    if !estimate.isApproved {
                        VStack(alignment: .leading, spacing: 10) {
                            EstimateSignaturePad(hasInk: $hasSignatureInk, controller: signatureController)
                                .frame(height: 200)

                            HStack {
                                Button("Clear") {
                                    signatureController.clear()
                                    hasSignatureInk = false
                                }
                                .buttonStyle(StormSecondaryButtonStyle())
                                .disabled(!hasSignatureInk || isSaving)

                                Spacer(minLength: 0)

                                Button {
                                    Task { await approveWithSignature() }
                                } label: {
                                    Label(
                                        isSaving ? "Approving…" : "Approve with signature",
                                        systemImage: "checkmark.seal.fill"
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(StormPrimaryButtonStyle())
                                .disabled(isSaving || !hasSignatureInk || estimate.lineItems.isEmpty)
                            }

                            Text("Customer must sign before the estimate can be approved.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let signedAt = estimate.signedAt {
                        Text("Signed \(APIDateFormatting.displayString(from: signedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if estimate.canCopyToVisit {
                        Text("Copy approved line items to a visit job.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if sourceVisitId != nil {
                            Button {
                                Task { await copyToVisit(target: "this_visit") }
                            } label: {
                                Label(
                                    isSaving ? "Copying…" : "Copy to this visit",
                                    systemImage: "doc.on.doc.fill"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(StormPrimaryButtonStyle())
                            .disabled(isSaving)
                        }

                        Button {
                            showCopyNewVisitConfirm = true
                        } label: {
                            Label("Copy to new visit", systemImage: "calendar.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .stormButtonStyle(primary: sourceVisitId == nil)
                        .disabled(isSaving)
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = estimate == nil
        error = nil
        defer { isLoading = false }
        do {
            let loaded: EstimateDetailDTO = try await env.apiClient.get(path: APIPath.estimate(estimateId))
            estimate = loaded
            customerHistory = try? await env.apiClient.get(
                path: APIPath.customerHistory(loaded.customer.id)
            )
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }


    private func sendEstimate() async {
        isSaving = true
        error = nil
        actionMessage = nil
        defer { isSaving = false }
        do {
            estimate = try await env.apiClient.post(path: APIPath.estimateSend(estimateId))
            actionMessage = "Estimate sent to customer"
            await onUpdated()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func approveWithSignature() async {
        guard let png = signatureController.pngData() else {
            error = "Customer signature is required"
            return
        }
        isSaving = true
        error = nil
        actionMessage = nil
        defer { isSaving = false }

        let base64 = png.base64EncodedString()
        let dataUrl = "data:image/png;base64,\(base64)"
        struct Body: Encodable { let signature: String }

        do {
            estimate = try await env.apiClient.post(
                path: APIPath.estimateSignature(estimateId),
                body: Body(signature: dataUrl)
            )
            actionMessage = "Estimate approved with signature"
            signatureController.clear()
            hasSignatureInk = false
            await onUpdated()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func copyToVisit(target: String) async {
        isSaving = true
        error = nil
        actionMessage = nil
        defer { isSaving = false }

        let body: EstimateCopyBody
        if target == "this_visit", let sourceVisitId {
            body = EstimateCopyBody(target: "this_visit", visitId: sourceVisitId, schedule: nil)
        } else {
            let start = Date()
            let end = start.addingTimeInterval(2 * 60 * 60)
            body = EstimateCopyBody(
                target: "new_visit",
                visitId: nil,
                schedule: EstimateCopyScheduleBody(
                    title: "Work from estimate",
                    startAt: VisitDateEditing.isoString(from: start),
                    endAt: VisitDateEditing.isoString(from: end),
                    division: sourceVisit?.division ?? "SERVICE",
                    zip: sourceVisit?.zip ?? sourceVisit?.property?.zip,
                    serviceAreaId: sourceVisit?.serviceArea?.id,
                    assignedUserId: sourceVisit?.assignedUser?.id,
                    address: sourceVisit?.address ?? sourceVisit?.property?.address,
                    city: sourceVisit?.city ?? sourceVisit?.property?.city,
                    state: sourceVisit?.state ?? sourceVisit?.property?.state
                )
            )
        }

        do {
            let response: EstimateCopyResponse = try await env.apiClient.post(
                path: APIPath.estimateCopy(estimateId),
                body: body
            )
            await load()
            await onUpdated()
            if target == "this_visit" && response.visitId == sourceVisitId {
                actionMessage = "Line items copied to this visit"
                dismiss()
            } else {
                actionMessage = "Line items copied to a new visit"
            }
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

/// Customer card for estimates — same contact/history UX as visits, without irrigation map.
struct EstimateCustomerInfoSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let customer: EstimateCustomerDTO
    let property: EstimatePropertyDTO?
    @ObservedObject var voice: VoiceManager
    var customerHistory: CustomerHistoryDTO? = nil

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                StormSectionHeader(title: "Customer", systemImage: "person.crop.circle")

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

                if let property {
                    Text(property.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(StormTheme.navy)
                }

                if let address = property?.formattedAddress {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let url = AppleMapsURL.directionsURL(
                        latitude: nil,
                        longitude: nil,
                        address: address
                    ) {
                        Link("Open in Maps", destination: url)
                            .font(.subheadline)
                            .foregroundStyle(StormTheme.sky)
                    }
                }

                DisclosureGroup {
                    VisitCustomerHistoryContent(history: customerHistory)
                } label: {
                    Label(historyDisclosureTitle, systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(StormTheme.navy)
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
}
