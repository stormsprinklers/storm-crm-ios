import SwiftUI

@MainActor
final class VisitDetailViewModel: ObservableObject {
    @Published var visit: VisitDetailDTO?
    @Published var checklists: [ChecklistDTO] = []
    @Published var timeEvents: [TimeEventDTO] = []
    @Published var customerHistory: CustomerHistoryDTO?
    @Published var isLoading = false
    @Published var isDeleting = false
    @Published var isSaving = false
    @Published var error: String?
    @Published var actionMessage: String?

    func load(api: APIClient, visitId: String, offlineSync: OfflineSyncManager? = nil) async {
        isLoading = visit == nil
        error = nil
        defer { isLoading = false }

        let useCache = {
            if let cached = offlineSync?.cachedVisitDetail(id: visitId) {
                visit = cached
                if checklists.isEmpty {
                    checklists = offlineSync?.cachedChecklists(visitId: visitId) ?? []
                }
                if timeEvents.isEmpty {
                    timeEvents = cached.timeEvents ?? []
                }
                error = nil
                return true
            }
            return false
        } as () -> Bool

        if offlineSync?.hasPendingChanges(forVisitId: visitId) == true {
            if useCache() {
                actionMessage = "Unsynced changes are saved on this device and will upload when you're online."
            }
            if offlineSync?.isOnline == true {
                offlineSync?.flushOutbox()
            }
            if visit != nil { return }
        }

        if offlineSync?.isOnline == false {
            if useCache() {
                actionMessage = "You're offline — changes will sync when you're back online."
            } else {
                error = "This visit isn't available offline. Open it once while you have a connection so it can be cached."
            }
            return
        }

        do {
            let visitData = try await api.getData(path: APIPath.visit(visitId))
            offlineSync?.cacheVisitDetailJSON(visitData, id: visitId)
            visit = try JSONCoding.makeDecoder().decode(VisitDetailDTO.self, from: visitData)
            if let checklistData = try? await api.getData(path: APIPath.visitChecklists(visitId)) {
                OfflineVisitDetailStore.saveChecklistsJSON(checklistData, visitId: visitId)
                checklists = (try? JSONCoding.makeDecoder().decode([ChecklistDTO].self, from: checklistData)) ?? []
            } else {
                checklists = (try? await api.get(path: APIPath.visitChecklists(visitId))) ?? checklists
            }
            timeEvents = (try? await api.get(path: APIPath.visitTime(visitId))) ?? []

            if let customerId = visit?.customer?.id {
                customerHistory = try? await api.get(
                    path: APIPath.customerHistory(customerId),
                    query: [URLQueryItem(name: "excludeVisitId", value: visitId)]
                )
            }
        } catch {
            if useCache() {
                actionMessage = "Showing cached visit — some details may be out of date."
            } else {
                self.error = (error as? APIError)?.message ?? error.localizedDescription
            }
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

    func addNote(
        api: APIClient,
        visitId: String,
        body: String,
        offlineSync: OfflineSyncManager?,
        author: NamedColor?
    ) async {
        struct Body: Encodable { let body: String }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        func queueOffline() -> Bool {
            guard let data = try? JSONCoding.makeEncoder().encode(Body(body: trimmed)) else { return false }
            offlineSync?.enqueue(
                path: APIPath.visitNotes(visitId),
                method: "POST",
                bodyData: data,
                relatedVisitId: visitId
            )
            let note = VisitNoteDTO(
                id: "offline-\(UUID().uuidString)",
                body: trimmed,
                createdAt: APIDateFormatting.queryString(from: Date()),
                author: author
            )
            if var current = visit {
                var notes = current.notes ?? []
                notes.append(note)
                current.notes = notes
                visit = current
            }
            offlineSync?.applyOfflineNote(visitId: visitId, note: note)
            actionMessage = "Note saved on this device — will sync when online"
            return true
        }

        if offlineSync?.isOnline == false {
            if !queueOffline() {
                actionMessage = "Could not save note offline."
            }
            return
        }
        do {
            let _: VisitNoteDTO = try await api.post(path: APIPath.visitNotes(visitId), body: Body(body: trimmed))
            await load(api: api, visitId: visitId, offlineSync: offlineSync)
        } catch {
            if offlineSync?.isOnline == false || isLikelyOffline(error) {
                if queueOffline() { return }
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

    func saveWorkSummary(
        api: APIClient,
        visitId: String,
        summary: String?,
        offlineSync: OfflineSyncManager?
    ) async -> Bool {
        struct Body: Encodable { let workSummary: String? }

        func queueOffline() -> Bool {
            guard let data = try? JSONCoding.makeEncoder().encode(Body(workSummary: summary)) else { return false }
            offlineSync?.enqueue(
                path: APIPath.visit(visitId),
                method: "PATCH",
                bodyData: data,
                relatedVisitId: visitId
            )
            if var current = visit {
                current.workSummary = summary
                visit = current
            }
            offlineSync?.applyOfflineWorkSummary(visitId: visitId, summary: summary)
            actionMessage = "Work summary saved on this device — will sync when online"
            return true
        }

        if offlineSync?.isOnline == false {
            return queueOffline()
        }
        do {
            let updated: VisitDetailDTO = try await api.patch(
                path: APIPath.visit(visitId),
                body: Body(workSummary: summary)
            )
            visit = updated
            offlineSync?.applyOfflineWorkSummary(visitId: visitId, summary: summary)
            return true
        } catch {
            if offlineSync?.isOnline == false || isLikelyOffline(error) {
                return queueOffline()
            }
            actionMessage = (error as? APIError)?.message ?? error.localizedDescription
            return false
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

    func cancelVisit(api: APIClient, visitId: String) async -> Bool {
        isSaving = true
        actionMessage = nil
        defer { isSaving = false }
        struct Body: Encodable { let status: String }
        do {
            visit = try await api.patch(path: APIPath.visit(visitId), body: Body(status: "CANCELLED"))
            actionMessage = "Visit cancelled"
            return true
        } catch {
            actionMessage = (error as? APIError)?.message ?? error.localizedDescription
            return false
        }
    }

    func updateTitle(api: APIClient, visitId: String, title: String) async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            actionMessage = "Title can’t be empty"
            return false
        }
        isSaving = true
        actionMessage = nil
        defer { isSaving = false }
        struct Body: Encodable { let title: String }
        do {
            visit = try await api.patch(path: APIPath.visit(visitId), body: Body(title: trimmed))
            actionMessage = "Title updated"
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
    @State private var showCancelConfirm = false
    @State private var showRescheduleSheet = false
    @State private var showEditTitle = false
    @State private var titleDraft = ""
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
                        // Leaves the still Street View header visible above the content card.
                        Color.clear.frame(height: 120)

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

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(visit.title)
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(StormTheme.navy)
                                    HStack(spacing: 8) {
                                        StormBadge(text: visit.status.visitDisplayLabel, style: .accent)
                                        if visit.isCallback == true {
                                            StormBadge(text: "Callback", style: .warning)
                                        }
                                        if env.offlineSync.hasPendingPayment(forVisitId: visitId) {
                                            StormBadge(text: "Payment pending sync", style: .warning)
                                        }
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

                                HStack(spacing: 10) {
                                    Button {
                                        activeSheet = .partsRun
                                    } label: {
                                        Label("Parts run", systemImage: "shippingbox.fill")
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(StormSecondaryButtonStyle())
                                    .frame(maxWidth: .infinity)

                                    Button {
                                        guard paymentSummary.hasBalanceDue else { return }
                                        activeSheet = .payment(amount: paymentAmountDue(for: visit))
                                    } label: {
                                        Group {
                                            if paymentSummary.isPaid {
                                                Label("Paid", systemImage: "checkmark.circle.fill")
                                            } else {
                                                Label {
                                                    Text(paymentAmountDue(for: visit), format: .currency(code: "USD"))
                                                } icon: {
                                                    Image(systemName: "creditcard.fill")
                                                }
                                            }
                                        }
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(
                                        StormPrimaryButtonStyle(
                                            tint: paymentSummary.isPaid ? StormTheme.lightGreen : StormTheme.coral
                                        )
                                    )
                                    .frame(maxWidth: .infinity)
                                    .disabled(!paymentSummary.hasBalanceDue)
                                    .opacity(paymentSummary.hasBalanceDue || paymentSummary.isPaid ? 1 : 0.55)
                                }

                                VisitWorkSummarySection(
                                    visitId: visitId,
                                    initialSummary: visit.workSummary
                                ) { summary in
                                    await viewModel.saveWorkSummary(
                                        api: env.apiClient,
                                        visitId: visitId,
                                        summary: summary,
                                        offlineSync: env.offlineSync
                                    )
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
                                                visitId: visitId,
                                                offlineSync: env.offlineSync
                                            )
                                        }
                                    )
                                }

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
                                    // Live from line items — visit.subtotal/total can lag after edits.
                                    subtotal: subtotal,
                                    discountTotal: discountTotal,
                                    total: total,
                                    onUpdated: { await reloadVisit() }
                                )

                                VisitNotesSection(
                                    notes: visit.notes ?? [],
                                    newNote: $newNote,
                                    onAdd: {
                                        let text = newNote
                                        await viewModel.addNote(
                                            api: env.apiClient,
                                            visitId: visitId,
                                            body: text,
                                            offlineSync: env.offlineSync,
                                            author: env.auth.user.map {
                                                NamedColor(id: $0.id, name: $0.name, color: nil, photoUrl: nil)
                                            }
                                        )
                                        newNote = ""
                                    }
                                )

                                VisitAttachmentsSection(visitId: visitId)

                                if visit.hasInstallPlan {
                                    VisitInstallPlanSection(visit: visit)
                                }

                                VisitScheduleEditSection(
                                    visit: visit,
                                    canEdit: canEditSchedule,
                                    onSaved: { await reloadVisit() }
                                )
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
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    StormAiChatView(visitId: visitId)
                } label: {
                    Image(systemName: "sparkles")
                        .accessibilityLabel("Storm AI")
                }
            }
            if env.auth.user != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            titleDraft = viewModel.visit?.title ?? ""
                            showEditTitle = true
                        } label: {
                            Label("Edit title", systemImage: "pencil")
                        }
                        .disabled(viewModel.visit == nil || viewModel.isSaving)

                        Button {
                            showRescheduleSheet = true
                        } label: {
                            Label("Reschedule", systemImage: "calendar")
                        }
                        .disabled(viewModel.visit == nil || viewModel.isSaving)

                        if let status = viewModel.visit?.status,
                           status != "CANCELLED",
                           status != "COMPLETED" {
                            Button(role: .destructive) {
                                showCancelConfirm = true
                            } label: {
                                Label("Cancel visit", systemImage: "xmark.circle")
                            }
                            .disabled(viewModel.isSaving)
                        }

                        if env.auth.user.map({ UserRoles.canDeleteVisit($0.role) }) == true {
                            Divider()
                            Button("Delete visit", role: .destructive) {
                                showDeleteConfirm = true
                            }
                            .disabled(viewModel.isDeleting)
                        }
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
                        visitId: visitId,
                        offlineSync: env.offlineSync
                    )
                }
                .environmentObject(env)
            }
        }
        .refreshable {
            await viewModel.load(api: env.apiClient, visitId: visitId, offlineSync: env.offlineSync)
        }
        .task {
            await viewModel.load(api: env.apiClient, visitId: visitId, offlineSync: env.offlineSync)
            syncLiveTracking()
        }
        .onChange(of: viewModel.visit?.status) { _, _ in
            syncLiveTracking()
        }
        .onDisappear {
            env.enRouteLocation.stop()
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
                if let visit = viewModel.visit {
                    activeSheet = .payment(amount: paymentAmountDue(for: visit))
                } else {
                    activeSheet = .payment(amount: finishBillingAmount)
                }
            }
            Button("Send invoice to customer") {
                Task { await sendInvoiceAfterFinish() }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text(
                "This job has \((viewModel.visit.map(paymentAmountDue(for:)) ?? finishBillingAmount).formatted(.currency(code: "USD"))) outstanding. Collect now or send an invoice?"
            )
        }
        .sheet(isPresented: $showRescheduleSheet) {
            if let visit = viewModel.visit {
                VisitScheduleEditSheet(visit: visit) {
                    await reloadVisit()
                }
                .environmentObject(env)
            }
        }
        .alert("Edit visit title", isPresented: $showEditTitle) {
            TextField("Title", text: $titleDraft)
            Button("Save") {
                Task {
                    _ = await viewModel.updateTitle(
                        api: env.apiClient,
                        visitId: visitId,
                        title: titleDraft
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Cancel this visit?",
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel visit", role: .destructive) {
                Task {
                    _ = await viewModel.cancelVisit(api: env.apiClient, visitId: visitId)
                    syncLiveTracking()
                }
            }
            Button("Keep visit", role: .cancel) {}
        } message: {
            Text("The visit stays on the customer record and counts toward cancellation reporting. It is not deleted.")
        }
        .alert("Are you sure you want to delete this visit?", isPresented: $showDeleteConfirm) {
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

    /// Balance due from current line items and discounts (minus any payments already recorded).
    private func paymentAmountDue(for visit: VisitDetailDTO) -> Double {
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
            offlineSync: env.offlineSync
        )
        // Keep the finish-billing prompt amount in sync if line items changed underneath it.
        if showFinishBillingPrompt, let visit = viewModel.visit {
            finishBillingAmount = paymentAmountDue(for: visit)
        }
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
        syncLiveTracking()
        // Payment is optional — prompt only, never block completion.
        if type == "FINISH",
           !(visit.lineItems ?? []).isEmpty,
           paymentSummary.hasBalanceDue {
            finishBillingAmount = paymentSummary.balanceDue ?? total
            showFinishBillingPrompt = true
        }
    }

    private func syncLiveTracking() {
        if viewModel.visit?.status == "EN_ROUTE" {
            env.enRouteLocation.start(visitId: visitId)
        } else {
            env.enRouteLocation.stop()
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