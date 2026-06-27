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
                actionMessage = "En route — ETA \(eta)"
            } else {
                actionMessage = "Updated: \(type.replacingOccurrences(of: "_", with: " "))"
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
            if viewModel.isLoading && viewModel.visit == nil {
                ProgressView()
            } else if let error = viewModel.error {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let visit = viewModel.visit {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        let subtotal = visitSubtotal(from: visit.lineItems ?? [])
                        let discountTotal = visitDiscountTotal(subtotal: subtotal, discounts: visit.discounts ?? [])
                        let total = max(0, subtotal - discountTotal)
                        let paymentSummary = VisitPaymentSummary.from(visit: visit, computedTotal: total)

                        VisitHeaderSection(visit: visit, paymentSummary: paymentSummary)

                        if visit.customer?.doNotService == true {
                            DoNotServiceBanner()
                        }

                        if let message = viewModel.actionMessage {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }

                        TimeTrackingBar(visit: visit, timeEvents: viewModel.timeEvents) { event in
                            await handleTimeEvent(event, visit: visit, total: total, paymentSummary: paymentSummary)
                        }

                        VisitPaymentsSection(
                            visitId: visitId,
                            total: total,
                            hasLineItems: !(visit.lineItems ?? []).isEmpty,
                            paymentSummary: paymentSummary,
                            onUpdated: { await reloadVisit() }
                        )

                        Button("Parts run") { showPartsRun = true }
                            .buttonStyle(StormSecondaryButtonStyle())
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if visit.hasInstallPlan {
                            VisitInstallPlanSection(visit: visit)
                        }

                        CustomerVisitCard(visit: visit, voice: env.voice)

                        JobMapView(
                            title: visit.title,
                            address: formattedJobAddress(visit),
                            latitude: mapLatitude(for: visit),
                            longitude: mapLongitude(for: visit)
                        )

                        if let property = visit.property, let customerId = visit.customer?.id {
                            VisitIrrigationSection(customerId: customerId, property: property)
                        }

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

                        let canEditSchedule = env.auth.user.map { UserRoles.canEditVisitOfficeFields($0.role) } ?? false

                        VisitScheduleEditSection(
                            visit: visit,
                            canEdit: canEditSchedule,
                            onSaved: { await reloadVisit() }
                        )
                        VisitTimeEventsSection(events: viewModel.timeEvents)
                        VisitTotalsSection(
                            subtotal: subtotal,
                            discountTotal: discountTotal,
                            total: total,
                            paymentSummary: paymentSummary
                        )

                        VisitLineItemsEditSection(
                            visitId: visitId,
                            items: visit.lineItems ?? [],
                            discounts: visit.discounts ?? [],
                            onUpdated: { await reloadVisit() }
                        )

                        VisitChecklistsSection(
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
                            }
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

                        if let estimates = visit.estimates, !estimates.isEmpty {
                            VisitEstimatesSection(estimates: estimates)
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
                }
                .background(StormTheme.page.ignoresSafeArea())
                .navigationTitle("Visit")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showPayment) {
                    PaymentSheet(
                        visitId: visitId,
                        amountDue: paymentAmountDue(for: visit)
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
                viewModel.actionMessage = "En route without GPS — ETA may be less accurate"
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
        let parts = [visit.address, visit.city, visit.state, visit.zip].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: ", ") }
        if let property = visit.property {
            let p = [property.address, property.city, property.state, property.zip].compactMap { $0 }.filter { !$0.isEmpty }
            return p.isEmpty ? nil : p.joined(separator: ", ")
        }
        return nil
    }

    private func mapLatitude(for visit: VisitDetailDTO) -> Double? {
        visit.property?.latitude
    }

    private func mapLongitude(for visit: VisitDetailDTO) -> Double? {
        visit.property?.longitude
    }
}

struct TimeTrackingBar: View {
    let visit: VisitDetailDTO
    let timeEvents: [TimeEventDTO]
    let onAction: (String) async -> Void

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Time tracking", systemImage: "timer")
                StormBadge(text: visit.status, style: .accent)
                if let eta = visit.eta?.formatted {
                    Text("ETA: \(eta)").font(.subheadline).foregroundStyle(StormTheme.sky)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                    ForEach(actionsForStatus(visit.status), id: \.type) { action in
                        Button(action.label) {
                            Task { await onAction(action.type) }
                        }
                        .buttonStyle(StormPrimaryButtonStyle())
                    }
                }
                if !timeEvents.isEmpty {
                    Text("Last: \(timeEvents.last?.type.replacingOccurrences(of: "_", with: " ") ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private struct Action {
        let type: String
        let label: String
    }

    private func actionsForStatus(_ status: String) -> [Action] {
        switch status {
        case "SCHEDULED", "UNSCHEDULED":
            return [Action(type: "EN_ROUTE", label: "En route")]
        case "EN_ROUTE":
            return [Action(type: "START", label: "Start job")]
        case "IN_PROGRESS":
            return [
                Action(type: "PAUSE", label: "Pause"),
                Action(type: "FINISH", label: "Finish"),
            ]
        case "PAUSED":
            return [
                Action(type: "RESUME", label: "Resume"),
                Action(type: "FINISH", label: "Finish"),
            ]
        default:
            return []
        }
    }
}

struct CustomerVisitCard: View {
    let visit: VisitDetailDTO
    @ObservedObject var voice: VoiceManager

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Customer", systemImage: "person.crop.circle")
                if let customer = visit.customer {
                    Text(customer.name).font(.title3.weight(.semibold))
                    if let email = customer.email, !email.isEmpty {
                        Link(destination: URL(string: "mailto:\(email)")!) {
                            Label(email, systemImage: "envelope")
                        }
                        .font(.subheadline)
                    }
                    if let phone = customer.phone, !phone.isEmpty {
                        HStack(spacing: 12) {
                            Link(destination: URL(string: "sms:\(phone)")!) {
                                Label("Text", systemImage: "message")
                            }
                            Button {
                                Task { await voice.call(phone: phone, customerId: customer.id) }
                            } label: {
                                Label("Call", systemImage: "phone")
                            }
                        }
                        .font(.subheadline)
                    }
                }
                if let address = formattedAddress(visit) {
                    Text(address).foregroundStyle(.secondary)
                    if let url = mapsURL(address) {
                        Link("Open in Maps", destination: url)
                            .font(.subheadline)
                            .foregroundStyle(StormTheme.sky)
                    }
                }
            }
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
