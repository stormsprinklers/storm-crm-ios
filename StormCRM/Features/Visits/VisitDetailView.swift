import SwiftUI

@MainActor
final class VisitDetailViewModel: ObservableObject {
    @Published var visit: VisitDetailDTO?
    @Published var checklists: [ChecklistDTO] = []
    @Published var timeEvents: [TimeEventDTO] = []
    @Published var customerHistory: CustomerHistoryDTO?
    @Published var isLoading = false
    @Published var isDeleting = false
    @Published var error: String?
    @Published var actionMessage: String?

    func load(api: APIClient, visitId: String) async {
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

    func addNote(api: APIClient, visitId: String, body: String, offlineSync: OfflineSyncManager?) async {
        struct Body: Encodable { let body: String }
        if offlineSync?.isOnline == false {
            if let data = try? JSONCoding.makeEncoder().encode(Body(body: body)) {
                offlineSync?.enqueue(path: APIPath.visitNotes(visitId), method: "POST", bodyData: data)
                actionMessage = "Note saved offline — will sync when online"
            }
            return
        }
        do {
            let _: VisitNoteDTO = try await api.post(path: APIPath.visitNotes(visitId), body: Body(body: body))
            await load(api: api, visitId: visitId)
        } catch {
            if offlineSync?.isOnline == false || isLikelyOffline(error) {
                if let data = try? JSONCoding.makeEncoder().encode(Body(body: body)) {
                    offlineSync?.enqueue(path: APIPath.visitNotes(visitId), method: "POST", bodyData: data)
                    actionMessage = "Note saved offline — will sync when online"
                    return
                }
            }
            actionMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func saveChecklistItem(
        api: APIClient,
        visitId: String,
        checklistId: String,
        itemId: String,
        response: JSONValue,
        offlineSync: OfflineSyncManager?
    ) async {
        struct Body: Encodable { let response: JSONValue }
        if offlineSync?.isOnline == false {
            if let data = try? JSONCoding.makeEncoder().encode(Body(response: response)) {
                offlineSync?.enqueue(
                    path: APIPath.visitChecklistItem(visitId, checklistId: checklistId, itemId: itemId),
                    method: "PATCH",
                    bodyData: data
                )
                actionMessage = "Saved offline — will sync when online"
            }
            return
        }
        do {
            let _: ChecklistItemDTO = try await api.patch(
                path: APIPath.visitChecklistItem(visitId, checklistId: checklistId, itemId: itemId),
                body: Body(response: response)
            )
            checklists = (try? await api.get(path: APIPath.visitChecklists(visitId))) ?? checklists
        } catch {
            if offlineSync?.isOnline == false || isLikelyOffline(error) {
                if let data = try? JSONCoding.makeEncoder().encode(Body(response: response)) {
                    offlineSync?.enqueue(
                        path: APIPath.visitChecklistItem(visitId, checklistId: checklistId, itemId: itemId),
                        method: "PATCH",
                        bodyData: data
                    )
                    actionMessage = "Saved offline — will sync when online"
                    return
                }
            }
            actionMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
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
    @State private var activeSheet: VisitActiveSheet?
    @State private var showFinishBillingPrompt = false
    @State private var finishBillingAmount: Double = 0
    @State private var showDeleteConfirm = false
    @State private var newNote = ""

    private enum VisitActiveSheet: Identifiable {
        case payment(amount: Double)
        case partsRun

        var id: String {
            switch self {
            case .payment: return "payment"
            case .partsRun: return "partsRun"
            }
        }
    }

    var body: some View {
        Group {
            if let visit = viewModel.visit {
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
                                let canEditSchedule = env.auth.user != nil

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
                                            } else if env.offlineSync.hasPendingPayment(forVisitId: visitId) {
                                                StormBadge(text: "Payment pending sync", style: .warning)
                                            }
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if paymentSummary.hasBalanceDue {
                                        Button {
                                            let amount = paymentSummary.balanceDue ?? total
                                            finishBillingAmount = amount
                                            activeSheet = .payment(amount: amount)
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
                                        .buttonStyle(.borderless)
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

                                Button {
                                    activeSheet = .partsRun
                                } label: {
                                    Label("Parts run", systemImage: "shippingbox.fill")
                                        .font(.body.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(StormSecondaryButtonStyle())

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
                                            response: response,
                                            offlineSync: env.offlineSync
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

                                VisitCustomerInfoSection(
                                    visit: visit,
                                    voice: env.voice,
                                    customerHistory: viewModel.customerHistory
                                )

                                if let role = env.auth.user?.role, UserRoles.canViewMaintenancePlans(role) {
                                    VisitMaintenanceSection(
                                        visitId: visitId,
                                        userRole: role,
                                        onUpdated: {
                                            await viewModel.load(
                                                api: env.apiClient,
                                                visitId: visitId
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

                                LineItemsSummarySection(
                                    owner: .visit(id: visitId),
                                    items: visit.lineItems ?? [],
                                    discounts: visit.discounts ?? [],
                                    subtotal: visit.subtotal ?? (visit.lineItems ?? []).reduce(0) { $0 + $1.total },
                                    discountTotal: max(
                                        0,
                                        (visit.subtotal ?? (visit.lineItems ?? []).reduce(0) { $0 + $1.total })
                                            - (visit.total ?? 0)
                                    ),
                                    total: visit.total
                                        ?? max(
                                            0,
                                            (visit.subtotal ?? (visit.lineItems ?? []).reduce(0) { $0 + $1.total })
                                        ),
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
                                            offlineSync: env.offlineSync
                                        )
                                    }
                                )

                                VisitAttachmentsSection(visitId: visitId)

                                if visit.hasInstallPlan {
                                    VisitInstallPlanSection(visit: visit)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(StormTheme.page)
                                    .shadow(color: StormTheme.navy.opacity(0.08), radius: 12, y: -4)
                            }
                            .contentShape(Rectangle())
                        }
                }
                .background(alignment: .top) {
                    // Background only — keeps the header out of the hit-test tree entirely.
                    VisitStreetViewHeader(addressQuery: formattedJobAddress(visit))
                        .allowsHitTesting(false)
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
        .toolbar {
            if env.auth.user.map({ UserRoles.canDeleteVisit($0.role) }) == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Delete visit", role: .destructive) {
                            showDeleteConfirm = true
                        }
                        .disabled(viewModel.isDeleting)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("More")
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .payment(let amount):
                PaymentSheet(visitId: visitId, amountDue: amount) {
                    Task { await reloadVisit() }
                }
                .environmentObject(env)
            case .partsRun:
                PartsRunSheet(visitId: visitId) {
                    await viewModel.load(
                        api: env.apiClient,
                        visitId: visitId
                    )
                }
                .environmentObject(env)
            }
        }
        .refreshable {
            await viewModel.load(api: env.apiClient, visitId: visitId)
        }
        .task {
            await viewModel.load(api: env.apiClient, visitId: visitId)
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
            Button("Collect payment now") {
                activeSheet = .payment(amount: finishBillingAmount)
            }
            Button("Send invoice to customer") {
                Task { await sendInvoiceAfterFinish() }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("This job has \(finishBillingAmount.formatted(.currency(code: "USD"))) outstanding. Collect now or send an invoice?")
        }
        .confirmationDialog(
            "Are you sure you want to delete this visit?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    if await viewModel.deleteVisit(api: env.apiClient, visitId: visitId) {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
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
            visitId: visitId
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
        if type == "FINISH" {
            let summary = (visit.workSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if summary.isEmpty {
                viewModel.actionMessage = "Add a work summary before completing the visit."
                return
            }
            let incompleteRequired = viewModel.checklists.contains { checklist in
                (checklist.requiredForCompletion == true) && checklist.completedAt == nil
            }
            if incompleteRequired {
                viewModel.actionMessage = "Complete required checklists before finishing."
                return
            }
        }

        await viewModel.postTimeEvent(
            api: env.apiClient,
            visitId: visitId,
            type: type,
            location: location
        )
        // Payment is optional — prompt only, never block completion.
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