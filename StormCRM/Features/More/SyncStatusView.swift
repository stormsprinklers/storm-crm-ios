import SwiftUI

struct SyncStatusView: View {
    @EnvironmentObject private var offlineSync: OfflineSyncManager
    @State private var mutations: [OutboxMutation] = []

    var body: some View {
        List {
            Section {
                LabeledContent("Network", value: offlineSync.isOnline ? "Online" : "Offline")
                LabeledContent("Pending changes", value: "\(offlineSync.pendingCount)")
                if offlineSync.isSyncing {
                    HStack {
                        ProgressView()
                        Text("Syncing…")
                            .foregroundStyle(.secondary)
                    }
                }
                if let lastError = offlineSync.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Visit notes and checklist updates made offline are queued here and sent when you're back online.")
            }

            Section("Outbox") {
                if mutations.isEmpty {
                    ContentUnavailableView(
                        "All synced",
                        systemImage: "checkmark.icloud",
                        description: Text("No pending or failed changes.")
                    )
                } else {
                    ForEach(mutations, id: \.id) { mutation in
                        OutboxMutationRow(mutation: mutation) {
                            offlineSync.retryMutation(id: mutation.id)
                            reload()
                        } onDelete: {
                            offlineSync.deleteMutation(id: mutation.id)
                            reload()
                        }
                    }
                }
            }
        }
        .navigationTitle("Sync status")
        .refreshable {
            offlineSync.flushOutbox()
            reload()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Sync now") {
                    offlineSync.flushOutbox()
                    reload()
                }
                .disabled(!offlineSync.isOnline || offlineSync.pendingCount == 0)
            }
        }
        .onAppear { reload() }
        .onChange(of: offlineSync.pendingCount) { _, _ in reload() }
    }

    private func reload() {
        mutations = offlineSync.pendingMutations().filter {
            $0.status == OutboxMutationStatus.pending.rawValue
                || $0.status == OutboxMutationStatus.failed.rawValue
        }
    }
}

private struct OutboxMutationRow: View {
    let mutation: OutboxMutation
    var onRetry: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(mutation.method)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StormTheme.sky)
                Text(shortPath(mutation.path))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                statusBadge
            }
            Text(mutation.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let lastError = mutation.lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 12) {
                if mutation.status == OutboxMutationStatus.failed.rawValue {
                    Button("Retry", action: onRetry)
                        .buttonStyle(StormSecondaryButtonStyle())
                }
                Button("Remove", role: .destructive, action: onDelete)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        let label = mutation.status.capitalized
        let style: StormBadge.Style = mutation.status == OutboxMutationStatus.failed.rawValue ? .warning : .accent
        return StormBadge(text: label, style: style)
    }

    private func shortPath(_ path: String) -> String {
        path.replacingOccurrences(of: "/api/", with: "")
    }
}
