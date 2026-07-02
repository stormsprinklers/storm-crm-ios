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
                                    Text(estimate.total, format: .currency(code: "USD"))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(StormTheme.navy)
                                    HStack(spacing: 6) {
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
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var error: String?
    @State private var actionMessage: String?
    @State private var showPicker = false
    @State private var showCopyNewVisitConfirm = false

    var body: some View {
        Group {
            if isLoading && estimate == nil {
                ProgressView("Loading estimate…")
            } else if let estimate {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(for: estimate)

                        if let actionMessage {
                            Text(actionMessage)
                                .font(.footnote)
                                .foregroundStyle(StormTheme.success)
                        }
                        if let error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }

                        lineItemsSection(for: estimate)
                        totalsSection(for: estimate)
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
        .navigationTitle("Estimate")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showPicker) {
            PriceBookPickerSheet { item in
                await addLineItem(from: item)
            }
        }
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
                    Text(estimate.total, format: .currency(code: "USD"))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(StormTheme.navy)
                    Spacer()
                    StormBadge(text: estimate.status)
                }
                Text(estimate.customer.name)
                    .font(.subheadline.weight(.medium))
                if let property = estimate.property {
                    Text(property.name).font(.caption).foregroundStyle(.secondary)
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
    private func lineItemsSection(for estimate: EstimateDetailDTO) -> some View {
        StormCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    StormSectionHeader(title: "Line items", systemImage: "list.bullet")
                    Spacer()
                    if estimate.status != "CONVERTED" {
                        Button("Add item") { showPicker = true }
                            .buttonStyle(StormSecondaryButtonStyle())
                            .disabled(isSaving)
                    }
                }

                if estimate.lineItems.isEmpty {
                    Text("Add items from the price book.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(estimate.lineItems) { item in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.subheadline.weight(.medium))
                                Text("\(item.quantity.formatted()) × \(item.unitPrice.formatted(.currency(code: "USD")))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(item.total, format: .currency(code: "USD"))
                                    .font(.subheadline.weight(.semibold))
                                if estimate.status != "CONVERTED" {
                                    Button("Remove", role: .destructive) {
                                        Task { await removeLineItem(item.id) }
                                    }
                                    .font(.caption)
                                    .disabled(isSaving)
                                }
                            }
                        }
                        if item.id != estimate.lineItems.last?.id {
                            Divider()
                        }
                    }
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
                        Button {
                            Task { await markApproved() }
                        } label: {
                            Label(isSaving ? "Saving…" : "Mark approved", systemImage: "checkmark.seal")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(StormSecondaryButtonStyle())
                        .disabled(isSaving || estimate.lineItems.isEmpty)
                    }

                    if estimate.canCopyToVisit {
                        Text("Copy approved line items to a visit job.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let sourceVisitId {
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
            estimate = try await env.apiClient.get(path: APIPath.estimate(estimateId))
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func addLineItem(from item: PriceBookItemDTO) async {
        let expectedUnitPrice = item.resolvedUnitPrice
        isSaving = true
        error = nil
        defer { isSaving = false }
        struct PatchBody: Encodable {
            let lineItemId: String
            let quantity: Double
            let unitPrice: Double
        }
        do {
            var updated = try await env.apiClient.post(
                path: APIPath.estimateLineItems(estimateId),
                body: AddEstimateLineItemBody(
                    priceBookItemId: item.id,
                    quantity: 1,
                    unitPrice: expectedUnitPrice
                )
            )
            if let added = PriceBookLineItemAdding.matchingLineItem(in: updated.lineItems, for: item),
               PriceBookLineItemAdding.needsPriceCorrection(lineItem: added, expectedUnitPrice: expectedUnitPrice) {
                updated = try await env.apiClient.patch(
                    path: APIPath.estimateLineItems(estimateId),
                    body: PatchBody(
                        lineItemId: added.id,
                        quantity: added.quantity,
                        unitPrice: expectedUnitPrice
                    )
                )
            }
            estimate = updated
            await onUpdated()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func removeLineItem(_ lineItemId: String) async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await env.apiClient.delete(
                path: APIPath.estimateLineItems(estimateId),
                query: [URLQueryItem(name: "lineItemId", value: lineItemId)]
            )
            await load()
            await onUpdated()
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

    private func markApproved() async {
        isSaving = true
        error = nil
        actionMessage = nil
        defer { isSaving = false }
        do {
            estimate = try await env.apiClient.patch(
                path: APIPath.estimate(estimateId),
                body: EstimateStatusBody(status: "APPROVED")
            )
            actionMessage = "Estimate marked approved"
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
