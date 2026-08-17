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
    @State private var approvalSheet: ApprovalSheetContext?
    @State private var showPostApproval = false
    @State private var postApprovalMode: EstimatePostApprovalSheet.InitialMode = .choose
    @State private var pendingPostApproval = false
    @State private var activeOptionId: String?
    @State private var showPresent = false
    @State private var optionNameDraft = ""
    @State private var optionNotesDraft = ""
    @FocusState private var optionNameFocused: Bool
    @FocusState private var optionNotesFocused: Bool

    private struct ApprovalSheetContext: Identifiable {
        let id = UUID()
        let total: Double
        let canApprove: Bool
    }

    var body: some View {
        Group {
            if isLoading && estimate == nil {
                ProgressView("Loading estimate…")
            } else if let estimate {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(for: estimate)

                        optionTabs(for: estimate)

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
                                optionId: currentOptionId(for: estimate)
                            ),
                            items: {
                                let optionId = currentOptionId(for: estimate)
                                if let optionId {
                                    return estimate.lineItems.filter {
                                        $0.optionId == optionId || $0.optionId == nil
                                    }
                                }
                                return estimate.lineItems
                            }(),
                            discounts: {
                                let optionId = currentOptionId(for: estimate)
                                if let optionId {
                                    return estimate.discounts.filter {
                                        $0.optionId == optionId || $0.optionId == nil
                                    }
                                }
                                return estimate.discounts
                            }(),
                            subtotal: currentOption(for: estimate)?.subtotal ?? estimate.subtotal,
                            discountTotal: currentOption(for: estimate)?.discountTotal ?? estimate.discountTotal,
                            total: currentOption(for: estimate)?.total ?? estimate.total,
                            canEdit: estimate.status != "CONVERTED"
                        ) {
                            await load()
                            await onUpdated()
                        }
                        if estimate.status == "APPROVED" || estimate.status == "CONVERTED" {
                            approvedBanner(for: estimate)
                        } else if estimate.status == "SENT" {
                            waitingForApprovalBanner
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
        .onChange(of: optionNameFocused) { _, focused in
            if !focused { Task { await saveOptionLabel() } }
        }
        .onChange(of: optionNotesFocused) { _, focused in
            if !focused { Task { await saveOptionNotes() } }
        }
        .fullScreenCover(item: $approvalSheet, onDismiss: {
            if pendingPostApproval {
                pendingPostApproval = false
                showPostApproval = true
            }
        }) { context in
            EstimateApprovalSheet(
                estimateTotal: context.total,
                canApprove: context.canApprove,
                isSaving: $isSaving
            ) { png in
                await approveWithSignature(pngData: png)
            }
            .environmentObject(env)
            .environmentObject(env.branding)
        }
        .fullScreenCover(isPresented: $showPostApproval) {
            EstimatePostApprovalSheet(
                estimateId: estimateId,
                estimateTotal: estimate?.total ?? 0,
                linkedVisitId: sourceVisitId ?? estimate?.visit?.id,
                optionId: estimate?.selectedOptionId ?? estimate?.options.first?.id,
                sourceVisit: sourceVisit,
                initialMode: postApprovalMode
            ) {
                await load()
                await onUpdated()
            }
            .environmentObject(env)
        }
        .fullScreenCover(isPresented: $showPresent) {
            EstimatePresentView(
                estimateId: estimateId,
                onUpdated: {
                    await load()
                    await onUpdated()
                },
                onApproveOption: { optionId, total in
                    activeOptionId = optionId
                    Task {
                        await selectOption(optionId)
                    }
                    approvalSheet = ApprovalSheetContext(total: total, canApprove: true)
                }
            )
            .environmentObject(env)
            .environmentObject(env.branding)
        }
        .task(id: estimate?.status) {
            guard estimate?.status == "SENT" else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { break }
                await load()
                if estimate?.status != "SENT" { break }
            }
        }
    }

    private var waitingForApprovalBanner: some View {
        StormCard {
            Text("Waiting for customer approval — this screen updates when they sign.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func approvedBanner(for estimate: EstimateDetailDTO) -> some View {
        StormCard {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(StormTheme.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text(estimate.status == "CONVERTED" ? "Estimate converted" : "Estimate approved")
                        .font(.headline)
                        .foregroundStyle(StormTheme.navy)
                    if let signedAt = estimate.signedAt {
                        Text("Customer signed \(APIDateFormatting.displayString(from: signedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
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

    private func currentOptionId(for estimate: EstimateDetailDTO) -> String? {
        if let activeOptionId, estimate.options.contains(where: { $0.id == activeOptionId }) {
            return activeOptionId
        }
        return estimate.selectedOptionId ?? estimate.options.first?.id
    }

    private func currentOption(for estimate: EstimateDetailDTO) -> EstimateOptionDTO? {
        let id = currentOptionId(for: estimate)
        return estimate.options.first(where: { $0.id == id }) ?? estimate.options.first
    }

    @ViewBuilder
    private func optionTabs(for estimate: EstimateDetailDTO) -> some View {
        StormCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    StormSectionHeader(title: "Options", systemImage: "square.stack")
                    Spacer()
                    Menu {
                        Button("Duplicate current") {
                            Task { await addOption(mode: "duplicate") }
                        }
                        Button("New blank") {
                            Task { await addOption(mode: "fresh") }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(StormTheme.sky)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(estimate.options) { option in
                            let selected = option.id == currentOptionId(for: estimate)
                            Button {
                                Task { await selectOption(option.id) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .font(.subheadline.weight(.semibold))
                                    Text(option.total, format: .currency(code: "USD"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selected ? StormTheme.sky.opacity(0.12) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selected ? StormTheme.sky : Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if estimate.status != "CONVERTED" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Option name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Option name", text: $optionNameDraft)
                            .textFieldStyle(.roundedBorder)
                            .focused($optionNameFocused)
                            .submitLabel(.done)
                            .onSubmit { Task { await saveOptionLabel() } }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes for AI")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Staff only. Helps write the homeowner description and pick a photo.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        TextField("Optional context for this option", text: $optionNotesDraft, axis: .vertical)
                            .lineLimit(3...8)
                            .textFieldStyle(.roundedBorder)
                            .focused($optionNotesFocused)
                    }
                }
            }
        }
    }

    private func selectOption(_ optionId: String) async {
        if optionNameFocused {
            await saveOptionLabel()
        }
        await saveOptionNotes()
        activeOptionId = optionId
        if let option = estimate?.options.first(where: { $0.id == optionId }) {
            optionNameDraft = option.label
            optionNotesDraft = option.internalNotes ?? ""
        }
        struct Body: Encodable { let optionId: String; let select: Bool }
        do {
            estimate = try await env.apiClient.patch(
                path: APIPath.estimateOptions(estimateId),
                body: Body(optionId: optionId, select: true)
            )
            syncOptionDrafts()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func syncOptionDrafts() {
        guard let estimate else { return }
        let option = currentOption(for: estimate) ?? estimate.options.first
        optionNameDraft = option?.label ?? ""
        optionNotesDraft = option?.internalNotes ?? ""
    }

    private func saveOptionLabel() async {
        guard let estimate, let optionId = currentOptionId(for: estimate) else { return }
        let trimmed = optionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentOption(for: estimate)?.label else { return }
        struct Body: Encodable { let optionId: String; let label: String }
        do {
            self.estimate = try await env.apiClient.patch(
                path: APIPath.estimateOptions(estimateId),
                body: Body(optionId: optionId, label: trimmed)
            )
            optionNameDraft = trimmed
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func saveOptionNotes() async {
        guard let estimate, let optionId = currentOptionId(for: estimate) else { return }
        let trimmed = optionNotesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = (currentOption(for: estimate)?.internalNotes ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != current else { return }
        struct Body: Encodable { let optionId: String; let internalNotes: String }
        do {
            self.estimate = try await env.apiClient.patch(
                path: APIPath.estimateOptions(estimateId),
                body: Body(optionId: optionId, internalNotes: trimmed)
            )
            optionNotesDraft = trimmed
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func addOption(mode: String) async {
        await saveOptionLabel()
        await saveOptionNotes()
        struct Body: Encodable {
            let mode: String
            let duplicateFromOptionId: String?
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let data: EstimateDetailDTO = try await env.apiClient.post(
                path: APIPath.estimateOptions(estimateId),
                body: Body(mode: mode, duplicateFromOptionId: mode == "duplicate" ? activeOptionId : nil)
            )
            estimate = data
            activeOptionId = data.options.last?.id
            syncOptionDrafts()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
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
                VStack(alignment: .leading, spacing: 8) {
                    StormSectionHeader(title: "Actions", systemImage: "bolt")

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(actionItems(for: estimate)) { item in
                            Button(action: item.action) {
                                VStack(spacing: 4) {
                                    Image(systemName: item.systemImage)
                                        .font(.body.weight(.semibold))
                                    Text(item.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(EstimateActionChipStyle(tint: item.tint))
                            .disabled(isSaving)
                            .accessibilityLabel(item.accessibilityLabel)
                        }
                    }

                    if !estimate.isApproved, estimate.lineItems.isEmpty {
                        Text("Add line items first, then collect the customer signature.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let signedAt = estimate.signedAt {
                        Text("Signed \(APIDateFormatting.displayString(from: signedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private struct EstimateActionItem: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let tint: Color
        let accessibilityLabel: String
        let action: () -> Void
    }

    private func actionItems(for estimate: EstimateDetailDTO) -> [EstimateActionItem] {
        var items: [EstimateActionItem] = []

        if estimate.status == "DRAFT" || estimate.status == "SENT" {
            items.append(
                EstimateActionItem(
                    id: "present",
                    title: "Present",
                    systemImage: "rectangle.on.rectangle",
                    tint: StormTheme.sky,
                    accessibilityLabel: "Present estimate"
                ) {
                    Task {
                        await saveOptionLabel()
                        await saveOptionNotes()
                        showPresent = true
                    }
                }
            )
            items.append(
                EstimateActionItem(
                    id: "send",
                    title: isSaving ? "Sending…" : "Send",
                    systemImage: "paperplane.fill",
                    tint: StormTheme.coral,
                    accessibilityLabel: "Send to customer"
                ) {
                    Task { await sendEstimate() }
                }
            )
        }

        if !estimate.isApproved {
            items.append(
                EstimateActionItem(
                    id: "approve",
                    title: "Approve",
                    systemImage: "checkmark.seal.fill",
                    tint: StormTheme.success,
                    accessibilityLabel: "Approve with signature"
                ) {
                    error = nil
                    approvalSheet = ApprovalSheetContext(
                        total: estimate.total,
                        canApprove: !estimate.lineItems.isEmpty
                    )
                }
            )
        }

        if let url = estimate.financingUrl, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(
                EstimateActionItem(
                    id: "financing",
                    title: isSaving ? "Texting…" : "Financing",
                    systemImage: "banknote",
                    tint: StormTheme.brandNavy,
                    accessibilityLabel: "Send financing link"
                ) {
                    Task { await sendFinancing() }
                }
            )
        }

        if estimate.canCopyToVisit {
            items.append(
                EstimateActionItem(
                    id: "today",
                    title: "Today",
                    systemImage: "sun.max.fill",
                    tint: Color.orange,
                    accessibilityLabel: "Complete today"
                ) {
                    postApprovalMode = .today
                    showPostApproval = true
                }
            )
            items.append(
                EstimateActionItem(
                    id: "schedule",
                    title: "Schedule",
                    systemImage: "calendar.badge.checkmark",
                    tint: StormTheme.sky,
                    accessibilityLabel: "Schedule visit"
                ) {
                    postApprovalMode = .schedule
                    showPostApproval = true
                }
            )
        }

        return items
    }

    private func load() async {
        isLoading = estimate == nil
        error = nil
        defer { isLoading = false }
        do {
            let loaded: EstimateDetailDTO = try await env.apiClient.get(path: APIPath.estimate(estimateId))
            estimate = loaded
            if activeOptionId == nil || !(loaded.options.contains { $0.id == activeOptionId }) {
                activeOptionId = loaded.selectedOptionId ?? loaded.options.first?.id
            }
            syncOptionDrafts()
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

    private func sendFinancing() async {
        isSaving = true
        error = nil
        actionMessage = nil
        defer { isSaving = false }
        do {
            struct Ack: Decodable {
                let ok: Bool?
                let smsSent: Bool?
            }
            let _: Ack = try await env.apiClient.post(path: APIPath.estimateFinancing(estimateId))
            actionMessage = "Financing options texted to the customer"
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    /// Returns `nil` on success, otherwise an error message for the approval popup.
    private func approveWithSignature(pngData: Data) async -> String? {
        isSaving = true
        error = nil
        actionMessage = nil
        defer { isSaving = false }

        let base64 = pngData.base64EncodedString()
        let dataUrl = "data:image/png;base64,\(base64)"
        struct Body: Encodable { let signature: String; let selectedOptionId: String? }

        do {
            // Accept any 2xx body shape, then reload the estimate detail.
            let _: EmptyResponse = try await env.apiClient.post(
                path: APIPath.estimateSignature(estimateId),
                body: Body(signature: dataUrl, selectedOptionId: activeOptionId)
            )
            await load()
            actionMessage = "Estimate approved with signature"
            postApprovalMode = .choose
            pendingPostApproval = true
            approvalSheet = nil
            await onUpdated()
            return nil
        } catch {
            let message = (error as? APIError)?.message ?? error.localizedDescription
            self.error = message
            return message
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

private struct EstimateActionChipStyle: ButtonStyle {
    var tint: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(tint.opacity(backgroundOpacity(configuration)))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func backgroundOpacity(_ configuration: Configuration) -> Double {
        if !isEnabled { return 0.45 }
        return configuration.isPressed ? 0.8 : 1
    }
}
