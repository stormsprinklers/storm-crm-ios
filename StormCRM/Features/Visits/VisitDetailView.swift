import SwiftUI

@MainActor
final class VisitDetailViewModel: ObservableObject {
    @Published var visit: VisitDetailDTO?
    @Published var checklists: [ChecklistDTO] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var actionMessage: String?

    func load(api: APIClient, visitId: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            visit = try await api.get(path: APIPath.visit(visitId))
            checklists = (try? await api.get(path: APIPath.visitChecklists(visitId))) ?? []
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
            let _: VisitDetailDTO = try await api.post(path: APIPath.visitTime(visitId), body: body)
            await load(api: api, visitId: visitId)
            actionMessage = "Updated: \(type.replacingOccurrences(of: "_", with: " "))"
        } catch {
            actionMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func addNote(api: APIClient, visitId: String, body: String) async {
        struct Body: Encodable { let body: String }
        do {
            let _: VisitNoteDTO = try await api.post(path: APIPath.visitNotes(visitId), body: Body(body: body))
            await load(api: api, visitId: visitId)
        } catch {
            actionMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func toggleChecklistItem(
        api: APIClient,
        visitId: String,
        checklistId: String,
        itemId: String,
        completed: Bool
    ) async {
        struct Body: Encodable { let response: Bool }
        do {
            let _: ChecklistItemDTO = try await api.patch(
                path: APIPath.visitChecklistItem(visitId, checklistId: checklistId, itemId: itemId),
                body: Body(response: completed)
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
                        TimeTrackingBar(visit: visit) { event in
                            await handleTimeEvent(event)
                        }

                        if let message = viewModel.actionMessage {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }

                        CustomerVisitCard(visit: visit, voice: env.voice)

                        if let property = visit.property, let customerId = visit.customer?.id {
                            NavigationLink {
                                IrrigationReadOnlyView(
                                    customerId: customerId,
                                    propertyId: property.id,
                                    propertyName: property.name ?? "Property"
                                )
                            } label: {
                                Label("Irrigation map & program", systemImage: "drop.fill")
                            }
                        }

                        VisitChecklistsSection(
                            checklists: viewModel.checklists,
                            onToggle: { checklistId, itemId, completed in
                                await viewModel.toggleChecklistItem(
                                    api: env.apiClient,
                                    visitId: visitId,
                                    checklistId: checklistId,
                                    itemId: itemId,
                                    completed: completed
                                )
                            }
                        )

                        VisitNotesSection(
                            notes: visit.notes ?? [],
                            newNote: $newNote,
                            onAdd: {
                                let text = newNote
                                newNote = ""
                                await viewModel.addNote(api: env.apiClient, visitId: visitId, body: text)
                            }
                        )

                        VisitAttachmentsSection(visitId: visitId)

                        LineItemsSection(items: visit.lineItems ?? [], total: visit.total)

                        HStack {
                            Button("Parts run") { showPartsRun = true }
                                .buttonStyle(.bordered)
                            Button("Collect payment") { showPayment = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                }
                .navigationTitle(visit.title)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showPayment) {
                    PaymentSheet(visitId: visitId)
                }
                .sheet(isPresented: $showPartsRun) {
                    PartsRunSheet(visitId: visitId)
                }
            }
        }
        .refreshable { await viewModel.load(api: env.apiClient, visitId: visitId) }
        .task { await viewModel.load(api: env.apiClient, visitId: visitId) }
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
    let onAction: (String) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time tracking").font(.headline)
            StatusBadge(status: visit.status)
            if let eta = visit.eta?.formatted {
                Text("ETA: \(eta)").font(.subheadline)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                ForEach(actionsForStatus(visit.status), id: \.self) { action in
                    Button(action.label) {
                        Task { await onAction(action.type) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Customer").font(.headline)
            if let customer = visit.customer {
                Text(customer.name).font(.title3)
                if let phone = customer.phone, !phone.isEmpty {
                    HStack {
                        Link(destination: URL(string: "sms:\(phone)")!) {
                            Label("Text", systemImage: "message")
                        }
                        Button {
                            Task { await voice.call(phone: phone) }
                        } label: {
                            Label("Call", systemImage: "phone")
                        }
                    }
                }
            }
            if let address = formattedAddress(visit) {
                Text(address).foregroundStyle(.secondary)
                if let url = mapsURL(address) {
                    Link("Open in Maps", destination: url)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
