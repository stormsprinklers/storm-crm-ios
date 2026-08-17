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
    @State private var renameOptionId: String?
    @State private var renameDraft = ""
    @State private var showResendConfirm = false

    private let canvasGray = Color(uiColor: .systemGray6)

    private var ranked: [EstimateOptionDTO] {
        (estimate?.options ?? [])
            .filter { $0.declinedAt == nil }
            .sorted { $0.total > $1.total }
    }

    /// Match the portal: clamp every card to the shortest description so heights line up.
    private var descriptionLineLimit: Int {
        let lines = ranked.map { approxDescriptionLines($0.description ?? "") }
        return max(1, lines.min() ?? 2)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                canvasGray.ignoresSafeArea()
                Group {
                    if isLoading && estimate == nil {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Preparing photos and descriptions…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error, estimate == nil {
                        ContentUnavailableView(
                            "Could not present",
                            systemImage: "exclamationmark.triangle",
                            description: Text(error)
                        )
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(ranked) { option in
                                    presentCard(option)
                                }
                            }
                            .padding()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("Present estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(canvasGray, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(canvasGray, for: .bottomBar)
            .toolbarBackground(.visible, for: .bottomBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Save and exit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save and send") {
                        if estimate?.hasBeenSent == true {
                            showResendConfirm = true
                        } else {
                            Task { await sendAndClose() }
                        }
                    }
                }
                if let url = estimate?.financingUrl, !url.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Explore financing options") {
                            Task { await sendFinancing() }
                        }
                    }
                }
            }
            .sheet(item: Binding(
                get: { openOptionId.map { PresentedOption(id: $0) } },
                set: { openOptionId = $0?.id }
            )) { presented in
                if let option = ranked.first(where: { $0.id == presented.id }), let estimate {
                    optionDetail(option, estimate: estimate)
                        .environmentObject(env)
                }
            }
            .task { await prepare() }
            .alert("Rename option", isPresented: Binding(
                get: { renameOptionId != nil },
                set: { if !$0 { renameOptionId = nil } }
            )) {
                TextField("Option name", text: $renameDraft)
                Button("Save") {
                    Task { await saveRename() }
                }
                Button("Cancel", role: .cancel) {
                    renameOptionId = nil
                }
            }
            .alert("Are you sure you want to send this estimate again?", isPresented: $showResendConfirm) {
                Button("Send again") {
                    Task { await sendAndClose() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func presentCard(_ option: EstimateOptionDTO) -> some View {
        let description = option.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let showMore = !description.isEmpty && approxDescriptionLines(description) > descriptionLineLimit

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(option.label)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button {
                    renameDraft = option.label
                    renameOptionId = option.id
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(StormTheme.sky)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Rename option")
            }
            .padding()
            presentPhoto(url: option.photoUrl, height: 160)
            VStack(alignment: .leading, spacing: 4) {
                Text(description.isEmpty ? " " : description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(descriptionLineLimit)
                if showMore {
                    Button {
                        openOptionId = option.id
                    } label: {
                        HStack(spacing: 2) {
                            Text("… More")
                            Image(systemName: "chevron.down")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(StormTheme.sky)
                    }
                    .buttonStyle(.plain)
                }
            }
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

    private func approxDescriptionLines(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 1 }
        return trimmed.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { count, paragraph in
            count + max(1, Int(ceil(Double(paragraph.count) / 48.0)))
        }
    }

    private func presentPhoto(url: String?, height: CGFloat) -> some View {
        Color(uiColor: .secondarySystemFill)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                if let url, !url.isEmpty {
                    AuthenticatedBlobImage(urlString: url, contentMode: .fill)
                }
            }
            .clipped()
    }

    private func optionDetail(_ option: EstimateOptionDTO, estimate: EstimateDetailDTO) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                presentPhoto(url: option.photoUrl, height: 220)
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
            }
            .background(Color(uiColor: .systemGroupedBackground))
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

    private func saveRename() async {
        guard let optionId = renameOptionId else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renameOptionId = nil
        guard !trimmed.isEmpty else { return }
        struct Body: Encodable { let optionId: String; let label: String }
        do {
            estimate = try await env.apiClient.patch(
                path: APIPath.estimateOptions(estimateId),
                body: Body(optionId: optionId, label: trimmed)
            )
            await onUpdated()
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

    private func sendFinancing() async {
        do {
            struct Ack: Decodable {
                let ok: Bool?
                let smsSent: Bool?
            }
            let _: Ack = try await env.apiClient.post(path: APIPath.estimateFinancing(estimateId))
            error = nil
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

private struct PresentedOption: Identifiable {
    let id: String
}
