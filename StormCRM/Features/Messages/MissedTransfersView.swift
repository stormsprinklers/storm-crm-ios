import SwiftUI

struct MissedTransfersView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var transfers: [MissedTransferDTO] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        List {
            if isLoading && transfers.isEmpty {
                ProgressView()
            } else if let error {
                Text(error).foregroundStyle(.red)
            } else if transfers.isEmpty {
                Text("No missed transfers in the last two weeks.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(transfers) { transfer in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transfer.customer?.name ?? transfer.fromNumber ?? "Unknown caller")
                            .font(.headline)
                        Text(APIDateFormatting.displayString(from: transfer.startedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let phone = transfer.fromNumber ?? transfer.customer?.phone {
                            Button("Call back") {
                                Task { await env.voice.call(phone: phone, customerId: transfer.customerId) }
                            }
                            .buttonStyle(StormSecondaryButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Missed transfers")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let response: MissedTransfersResponse = try await env.apiClient.get(path: APIPath.mobileMissedTransfers)
            transfers = response.transfers
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
