import SwiftUI

struct EstimatePresentView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let estimateId: String
    var onUpdated: () async -> Void
    var onApproveOption: (String, Double) -> Void

    @State private var estimate: EstimateDetailDTO?
    @State private var isLoading = true
    @State private var error: String?
    @State private var openOptionId: String?
    @State private var isDeclining = false

    private var ranked: [EstimateOptionDTO] {
        (estimate?.options ?? [])
            .filter { $0.declinedAt == nil }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && estimate == nil {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Preparing photos and descriptions…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let error, estimate == nil {
                    ContentUnavailableView("Could not present", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(ranked) { option in
                                presentCard(option)
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Color(uiColor: .systemGray6).ignoresSafeArea())
            .navigationTitle("Present estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Save") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save and send") {
                        Task { await sendAndClose() }
                    }
                }
            }
            .sheet(item: Binding(
                get: { openOptionId.map { PresentedOption(id: $0) } },
                set: { openOptionId = $0?.id }
            )) { presented in
                if let option = ranked.first(where: { $0.id == presented.id }), let estimate {
                    optionDetail(option, estimate: estimate)
                }
            }
            .task { await prepare() }
        }
    }

    private func presentCard(_ option: EstimateOptionDTO) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(option.label)
                .font(.title3.weight(.bold))
                .padding()
            AsyncImage(url: option.photoUrl.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.gray.opacity(0.2)
                }
            }
            .frame(height: 160)
            .clipped()
            Text(option.description ?? " ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
            HStack {
                Text(option.total, format: .currency(code: "USD"))
                    .font(.headline)
                Spacer()
                Button("View option") { openOptionId = option.id }
                    .buttonStyle(StormPrimaryButtonStyle())
            }
            .padding()
        }
        .frame(width: 300)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    private func optionDetail(_ option: EstimateOptionDTO, estimate: EstimateDetailDTO) -> some View {
        NavigationStack {
            List {
                Section {
                    Text(option.total, format: .currency(code: "USD"))
                        .font(.title2.weight(.bold))
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                    }
                }
                Section("Line items") {
                    ForEach(estimate.lineItems.filter { $0.optionId == option.id || $0.optionId == nil }) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name)
                                if let description = item.description, !description.isEmpty {
                                    Text(description).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(item.displayTotal, format: .currency(code: "USD"))
                        }
                    }
                }
                if estimate.status != "APPROVED" && estimate.status != "CONVERTED" {
                    Section {
                        Button("Approve this option") {
                            onApproveOption(option.id, option.total)
                            dismiss()
                        }
                        Button("Decline", role: .destructive) {
                            Task { await decline(option.id) }
                        }
                        .disabled(isDeclining)
                    }
                }
            }
            .navigationTitle(option.label)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { openOptionId = nil }
                }
            }
        }
    }

    private func prepare() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            estimate = try await env.apiClient.post(path: APIPath.estimatePresent(estimateId))
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func decline(_ optionId: String) async {
        isDeclining = true
        defer { isDeclining = false }
        struct Body: Encodable { let optionId: String; let declined: Bool }
        do {
            estimate = try await env.apiClient.patch(
                path: APIPath.estimateOptions(estimateId),
                body: Body(optionId: optionId, declined: true)
            )
            openOptionId = nil
            await onUpdated()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func sendAndClose() async {
        do {
            estimate = try await env.apiClient.post(path: APIPath.estimateSend(estimateId))
            await onUpdated()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

private struct PresentedOption: Identifiable {
    let id: String
}
