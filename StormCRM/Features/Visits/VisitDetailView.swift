import SwiftUI

@MainActor
final class VisitDetailViewModel: ObservableObject {
    @Published var visit: VisitDetailDTO?
    @Published var checklists: [ChecklistDTO] = []
    @Published var timeEvents: [TimeEventDTO] = []
    @Published var profit: VisitProfitDTO?
    @Published var customerHistory: CustomerHistoryDTO?
    @Published var isLoading = false
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
            actionMessage = "Updated: \(type.replacingOccurrences(of: "_", with: " "))"
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
}

struct VisitDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    let visitId: String
    @StateObject private var viewModel = VisitDetailViewModel()
    @State private var showPayment = false
    @State private var showPartsRun = false
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
                            await handleTimeEvent(event)
                        }

                        HStack {
                            Button("Parts run") { showPartsRun = true }
                                .buttonStyle(StormSecondaryButtonStyle())
                            Button("Collect payment") { showPayment = true }
                                .buttonStyle(StormPrimaryButtonStyle())
                                .disabled(paymentSummary.isPaid || total <= 0)
                        }

                        if visit.hasInstallPlan {
                            VisitInstallPlanSection(visit: visit)
                        }

                        CustomerVisitCard(visit: visit, voice: env.voice)

                        if let property = visit.property {
                            VisitPropertyImagesSection(property: property)
                        }

                        if let property = visit.property, let customerId = visit.customer?.id {
                            NavigationLink {
                                IrrigationReadOnlyView(
                                    customerId: customerId,
                                    propertyId: property.id,
                                    propertyName: property.name ?? "Property"
                                )
                            } label: {
                                Label("Irrigation map & program", systemImage: "drop.fill")
                                    .foregroundStyle(StormTheme.sky)
                            }
                        }

                        VisitScheduleInfoSection(visit: visit)
                        VisitTimeEventsSection(events: viewModel.timeEvents)
                        VisitTotalsSection(
                            subtotal: subtotal,
                            discountTotal: discountTotal,
                            total: total,
                            paymentSummary: paymentSummary
                        )

                        LineItemsSection(
                            items: visit.lineItems ?? [],
                            discounts: visit.discounts ?? [],
                            subtotal: subtotal,
                            discountTotal: discountTotal,
                            total: total
                        )

                        VisitChecklistsSection(checklists: viewModel.checklists) { checklistId, itemId, response in
                            await viewModel.saveChecklistItem(
                                api: env.apiClient,
                                visitId: visitId,
                                checklistId: checklistId,
                                itemId: itemId,
                                response: response
                            )
                        }

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
                    }
                    .padding()
                }
                .background(StormTheme.page.ignoresSafeArea())
                .navigationTitle("Visit")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showPayment) {
                    PaymentSheet(visitId: visitId)
                }
                .sheet(isPresented: $showPartsRun) {
                    PartsRunSheet(visitId: visitId)
                }
            }
        }
        .refreshable {
            await viewModel.load(api: env.apiClient, visitId: visitId, userRole: env.auth.user?.role)
        }
        .task {
            await viewModel.load(api: env.apiClient, visitId: visitId, userRole: env.auth.user?.role)
        }
    }

    private func handleTimeEvent(_ type: String) async {
        if type == "EN_ROUTE" {
            env.location.requestPermission()
            env.location.refreshLocation()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        let loc = env.location.lastLocation
        await viewModel.postTimeEvent(
            api: env.apiClient,
            visitId: visitId,
            type: type,
            location: loc.map { ($0.coordinate.latitude, $0.coordinate.longitude) }
        )
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
