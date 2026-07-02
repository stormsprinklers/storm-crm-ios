import SwiftUI

@MainActor
final class VisitDetailViewModel: ObservableObject {
    @Published var visit: VisitDetailDTO?
    @Published var checklists: [ChecklistDTO] = []
    @Published var timeEvents: [TimeEventDTO] = []
    @Published var profit: VisitProfitDTO?
    @Published var customerHistory: CustomerHistoryDTO?
    @Published var isLoading = false
    @Published var isDeleting = false
    @Published var error: String?
    @Published var actionMessage: String?

    func load(api: APIClient, visitId: String, userRole: String?) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            visit = try await api.get(path: APIPath.visit(visitId))
            checklists = (try? await api.get(path: APIPath.visitChecklists(visitId))) ?? []
            timeEvents = (try? await api.get(path: APIPath.visitTime(visitId))) ?? []

            if let customerId = visit?.customer?.id {
                customerHistory = try? await api.get(
                    path: APIPath.customerHistory(customerId),
                    query: [URLQueryItem(name: "excludeVisitId", value: visitId)]
                )
            }

            if let role = userRole, UserRoles.canViewProfitMargins(role) {
                profit = try? await api.get(path: APIPath.visitProfit(visitId))
            }
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func postTimeEvent(
        api: APIClient,
        visitId: String,
        type: String,
        location: (lat: Double, lng: Double)?
    ) async {
        struct Body: Encodable {
            let type: String
            let originLat: Double?
            let originLng: Double?
        }
        do {
            let body = Body(
                type: type,
                originLat: location?.lat,
                originLng: location?.lng
            )
            visit = try await api.post(path: APIPath.visitTime(visitId), body: body)
            timeEvents = (try? await api.get(path: APIPath.visitTime(visitId))) ?? timeEvents
            if type == "EN_ROUTE", let eta = visit?.eta?.formatted {
                actionMessage = "On my way — ETA \(eta)"
            } else {
                actionMessage = "Updated: \(type.visitDisplayLabel)"
            }
        } catch {
            actionMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func addNote(api: APIClient, visitId: String, body: String, userRole: String?) async {
        struct Body: Encodable { let body: String }
        do {
            let _: VisitNoteDTO = try await api.post(path: APIPath.visitNotes(visitId), body: Body(body: body))
            await load(api: api, visitId: visitId, userRole: userRole)
        } catch {
            actionMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func saveChecklistItem(
        api: APIClient,
        visitId: String,
        checklistId: String,
        itemId: String,
        response: JSONValue
    ) async {
        struct Body: Encodable { let response: JSONValue }
        do {
            let _: ChecklistItemDTO = try await api.patch(
                path: APIPath.visitChecklistItem(visitId, checklistId: checklistId, itemId: itemId),
                body: Body(response: response)
            )
            checklists = (try? await api.get(path: APIPath.visitChecklists(visitId))) ?? checklists
        } catch {
            actionMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func completeChecklist(api: APIClient, visitId: String, checklistId: String) async {
        do {
            let _: EmptyResponse = try await api.post(
                path: APIPath.visitChecklistComplete(visitId, checklistId: checklistId)
            )
            checklists = (try? await api.get(path: APIPath.visitChecklists(visitId))) ?? checklists
            actionMessage = "Checklist completed"
        } catch {
            actionMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func assignChecklistTemplate(
        api: APIClient,
        visitId: String,
        templateId: String
    ) async {
        struct Body: Encodable { let templateId: String }
        do {
            let _: ChecklistDTO = try await api.post(
                path: APIPath.visitChecklists(visitId),
                body: Body(templateId: templateId)
            )
            checklists = (try? await api.get(path: APIPath.visitChecklists(visitId))) ?? checklists
            actionMessage = "Checklist added"
        } catch {
            actionMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func deleteVisit(api: APIClient, visitId: String) async -> Bool {
        isDeleting = true
        actionMessage = nil
        defer { isDeleting = false }
        do {
            try await api.delete(path: APIPath.visit(visitId))
            return true
        } catch {
            actionMessage = (error as? APIError)?.message ?? error.localizedDescription
            return false
        }
    }
}

struct VisitDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let visitId: String
    @StateObject private var viewModel = VisitDetailViewModel()
    @State private var showPayment = false
    @State private var showFinishBillingPrompt = false
    @State private var finishBillingAmount: Double = 0
    @State private var showPartsRun = false
    @State private var showDeleteConfirm = false
    @State private var newNote = ""

    var body: some View {
        Group {
            if let visit = viewModel.visit {
                ZStack(alignment: .top) {
                    VisitStreetViewHeader(addressQuery: formattedJobAddress(visit))

                    ScrollView {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 72)

                            VStack(alignment: .leading, spacing: 16) {
                                let subtotal = visitSubtotal(from: visit.lineItems ?? [])
                                let discountTotal = visitDiscountTotal(
                                    subtotal: subtotal,
                                    discounts: visit.discounts ?? []
                                )
                                let total = max(0, subtotal - discountTotal)
                                let paymentSummary = VisitPaymentSummary.from(
                                    visit: visit,
                                    computedTotal: total
                                )
                                let canEditSchedule = env.auth.user.map {
                                    UserRoles.canEditVisitOfficeFields($0.role)
                                } ?? false
                                let canEditTags = canEditSchedule

                                if visit.customer?.doNotService == true {
                                    DoNotServiceBanner()
                                }

                                if let message = viewModel.actionMessage {
                                    Text(message)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(visit.title)
                                            .font(.title2.weight(.semibold))
                                            .foregroundStyle(StormTheme.navy)
                                        HStack(spacing: 8) {
                                            StormBadge(text: visit.status.visitDisplayLabel, style: .accent)
                                            if visit.isCallback == true {
                                                StormBadge(text: "Callback", style: .warning)
                                            }
                                            if paymentSummary.isPaid {
                                                StormBadge(text: "Paid", style: .success)
                                            }
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if paymentSummary.hasBalanceDue {
                                        Button {
                                            finishBillingAmount = paymentSummary.balanceDue ?? total
                                            showPayment = true
                                        } label: {
                                            Label {
                                                Text(paymentAmountDue(for: visit), format: .currency(code: "USD"))
                                            } icon: {
                                                Image(systemName: "dollarsign.circle.fill")
                                            }
                                            .font(.subheadline.weight(.semibold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(StormTheme.coral)
                                            .foregroundStyle(.white)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                TimeTrackingBar(visit: visit, timeEvents: viewModel.timeEvents) { event in
                                    await handleTimeEvent(
                                        event,
                                        visit: visit,
                                        total: total,
                                        paymentSummary: paymentSummary
                                    )
                                }

                                VisitWorkSummarySection(
                                    visitId: visitId,
                                    initialSummary: visit.workSummary
                                ) {
                                    await reloadVisit()
                                }

                                VisitChecklistLauncherSection(
                                    checklists: viewModel.checklists,
                                    onSaveItem: { checklistId, itemId, response in
                                        await viewModel.saveChecklistItem(
                                            api: env.apiClient,
                                            visitId: visitId,
                                            checklistId: checklistId,
                                            itemId: itemId,
                                            response: response
                                        )
                                    },
                                    onComplete: { checklistId in
                                        await viewModel.completeChecklist(
                                            api: env.apiClient,
                                            visitId: visitId,
                                            checklistId: checklistId
                                        )
                                    },
                                    onAssignTemplate: { templateId in
                                        await viewModel.assignChecklistTemplate(
                                            api: env.apiClient,
                                            visitId: visitId,
                                            templateId: templateId
                                        )
                                    }
                                )

                                VisitCustomerInfoSection(visit: visit, voice: env.voice)

                                if let role = env.auth.user?.role, UserRoles.canViewMaintenancePlans(role) {
                                    VisitMaintenanceSection(
                                        visitId: visitId,
                                        userRole: role,
                                        onUpdated: {
                                            await viewModel.load(
                                                api: env.apiClient,
                                                visitId: visitId,
                                                userRole: role
                                            )
                                        }
                                    )
                                }

                                VisitScheduleEditSection(
                                    visit: visit,
                                    canEdit: canEditSchedule,
                                    onSaved: { await reloadVisit() }
                                )

                                VisitEstimatesSection(
                                    visit: visit,
                                    visitId: visitId
                                ) {
                                    await reloadVisit()
                                }

                                VisitLineItemsEditSection(
                                    visitId: visitId,
                                    items: visit.lineItems ?? [],
                                    discounts: visit.discounts ?? [],
                                    onUpdated: { await reloadVisit() }
                                )

                                VisitNotesSection(
                                    notes: visit.notes ?? [],
                                    newNote: $newNote,
                                    onAdd: {
                                        let text = newNote
                                        newNote = ""
                                        await viewModel.addNote(
                                            api: env.apiClient,
                                            visitId: visitId,
                                            body: text,
                                            userRole: env.auth.user?.role
                                        )
                                    }
                                )

                                VisitAttachmentsSection(visitId: visitId)

                                VisitTagsSection(
                                    visitId: visitId,
                                    tags: visit.tags ?? [],
                                    canEdit: canEditTags,
                                    onUpdated: { await reloadVisit() }
                                )

                                Button("Parts run") { showPartsRun = true }
                                    .buttonStyle(StormSecondaryButtonStyle())
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if visit.hasInstallPlan {
                                    VisitInstallPlanSection(visit: visit)
                                }

                                if let history = viewModel.customerHistory {
                                    VisitCustomerHistorySection(history: history)
                                }

                                if let profit = viewModel.profit {
                                    VisitProfitSectionView(profit: profit)
                                }

                                if env.auth.user.map({ UserRoles.canDeleteVisit($0.role) }) == true {
                                    deleteVisitSection(visit: visit)
                                }
                            }
                            .padding()
                            .background {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(StormTheme.page)
                                    .shadow(color: StormTheme.navy.opacity(0.08), radius: 12, y: -4)
                            }
                        }
                    }
                }
                .background(StormTheme.navy.opacity(0.08).ignoresSafeArea())
            } else if let error = viewModel.error {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView("Loading visit…")
            }
        }
        .navigationTitle("Visit")
        .navigationBarTitleDisplayMode(.inline)
        .customerHistoryDestinations()
        .sheet(isPresented: $showPayment) {
            PaymentSheet(
                visitId: visitId,
                amountDue: viewModel.visit.map { paymentAmountDue(for: $0) } ?? finishBillingAmount
            ) {
                Task { await reloadVisit() }
            }
        }
        .sheet(isPresented: $showPartsRun) {
            PartsRunSheet(visitId: visitId) {
                await viewModel.load(
                    api: env.apiClient,
                    visitId: visitId,
                    userRole: env.auth.user?.role
                )
            }
        }
        .refreshable {
            await viewModel.load(api: env.apiClient, visitId: visitId, userRole: env.auth.user?.role)
        }
        .task {
            await viewModel.load(api: env.apiClient, visitId: visitId, userRole: env.auth.user?.role)
        }
        .onReceive(NotificationCenter.default.publisher(for: .visitPaymentCompleted)) { notification in
            guard let visitId = notification.userInfo?["visitId"] as? String, visitId == self.visitId else { return }
            Task { await reloadVisit() }
        }
        .confirmationDialog(
            "Collect payment?",
            isPresented: $showFinishBillingPrompt,
            titleVisibility: .visible
        ) {
            Button("Collect payment now") { showPayment = true }
            Button("Send invoice to customer") {
                Task { await sendInvoiceAfterFinish() }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("This job has \(finishBillingAmount.formatted(.currency(code: "USD"))) outstanding. Collect now or send an invoice?")
        }
        .confirmationDialog(
            "Delete visit?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete visit", role: .destructive) {
                Task {
                    if await viewModel.deleteVisit(api: env.apiClient, visitId: visitId) {
                        dismiss()
                    }
                }
            }
        } message: {
            if let visit = viewModel.visit {
                Text("This will permanently delete “\(visit.title)” and its line items, notes, and attachments. This cannot be undone.")
            }
        }
    }

    @ViewBuilder
    private func deleteVisitSection(visit: VisitDetailDTO) -> some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Danger zone", systemImage: "exclamationmark.triangle")
                Text("Permanently remove this visit and all associated data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(viewModel.isDeleting ? "Deleting…" : "Delete visit") {
                    showDeleteConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(viewModel.isDeleting)
            }
        }
    }

    private func paymentAmountDue(for visit: VisitDetailDTO) -> Double {
        if finishBillingAmount > 0 { return finishBillingAmount }
        let subtotal = visitSubtotal(from: visit.lineItems ?? [])
        let discountTotal = visitDiscountTotal(subtotal: subtotal, discounts: visit.discounts ?? [])
        let total = max(0, subtotal - discountTotal)
        let summary = VisitPaymentSummary.from(visit: visit, computedTotal: total)
        return summary.balanceDue ?? total
    }

    private func reloadVisit() async {
        await viewModel.load(
            api: env.apiClient,
            visitId: visitId,
            userRole: env.auth.user?.role
        )
    }

    private func handleTimeEvent(
        _ type: String,
        visit: VisitDetailDTO,
        total: Double,
        paymentSummary: VisitPaymentSummary
    ) async {
        var location: (lat: Double, lng: Double)?
        if type == "EN_ROUTE" {
            if let loc = await env.location.awaitLocation(timeout: 12) {
                location = (loc.coordinate.latitude, loc.coordinate.longitude)
            } else {
                viewModel.actionMessage = "On my way without GPS — ETA may be less accurate"
            }
        }
        await viewModel.postTimeEvent(
            api: env.apiClient,
            visitId: visitId,
            type: type,
            location: location
        )
        if type == "FINISH",
           !(visit.lineItems ?? []).isEmpty,
           paymentSummary.hasBalanceDue {
            finishBillingAmount = paymentSummary.balanceDue ?? total
            showFinishBillingPrompt = true
        }
    }

    private func sendInvoiceAfterFinish() async {
        struct Body: Encodable { let send: Bool }
        do {
            let _: VisitInvoiceResponse = try await env.apiClient.post(
                path: APIPath.visitInvoice(visitId),
                body: Body(send: true)
            )
            viewModel.actionMessage = "Invoice sent to customer"
            await reloadVisit()
        } catch {
            viewModel.actionMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func formattedJobAddress(_ visit: VisitDetailDTO) -> String? {
        AppleMapsURL.formattedAddress(for: visit)
    }
}