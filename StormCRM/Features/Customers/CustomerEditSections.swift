import SwiftUI

struct CustomerTagsAndFlagsSection: View {
    let customer: CustomerDTO
    let canEditTags: Bool
    let canFlagDoNotService: Bool
    let onTagsUpdated: ([String]) async throws -> Void
    let onDoNotServiceUpdated: (Bool) async throws -> Void
    let onError: (String) -> Void

    @State private var tagDraft = ""
    @State private var isSavingTags = false
    @State private var isSavingFlag = false
    @State private var showEnableDnsConfirm = false
    @State private var showDisableDnsConfirm = false

    private var tags: [String] { customer.tags ?? [] }

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 14) {
                if canFlagDoNotService {
                    VStack(alignment: .leading, spacing: 8) {
                        StormSectionHeader(title: "Service status", systemImage: "exclamationmark.shield")
                        Toggle(isOn: dnsBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Do not service")
                                    .font(.subheadline.weight(.medium))
                                Text("Blocks new appointment booking for this customer.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isSavingFlag)
                    }

                    if canEditTags {
                        Divider()
                    }
                }

                if canEditTags {
                    VStack(alignment: .leading, spacing: 10) {
                        StormSectionHeader(title: "Tags", systemImage: "tag")
                        Text("Use tags to segment customers for marketing and notes in the field.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            TextField("Add tag…", text: $tagDraft)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Add") {
                                Task { await addTag() }
                            }
                            .buttonStyle(StormSecondaryButtonStyle())
                            .disabled(isSavingTags || tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if tags.isEmpty {
                            Text("No tags yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            FlowLayoutTags(tags: tags, onRemove: canEditTags ? { tag in
                                Task { await removeTag(tag) }
                            } : nil)
                        }
                    }
                } else if !tags.isEmpty {
                    StormSectionHeader(title: "Tags", systemImage: "tag")
                    FlowTagsView(tags: tags)
                }
            }
        }
        .confirmationDialog(
            "Mark as do not service?",
            isPresented: $showEnableDnsConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark do not service", role: .destructive) {
                Task { await saveDoNotService(true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This customer will be blocked from new appointment booking across the CRM.")
        }
        .confirmationDialog(
            "Clear do not service?",
            isPresented: $showDisableDnsConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear flag") {
                Task { await saveDoNotService(false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This customer can be booked for service again.")
        }
    }

    private var dnsBinding: Binding<Bool> {
        Binding(
            get: { customer.doNotService == true },
            set: { newValue in
                if newValue {
                    showEnableDnsConfirm = true
                } else {
                    showDisableDnsConfirm = true
                }
            }
        )
    }

    private func addTag() async {
        let tag = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !tags.contains(tag) else {
            tagDraft = ""
            return
        }
        isSavingTags = true
        defer { isSavingTags = false }
        do {
            try await onTagsUpdated(tags + [tag])
            tagDraft = ""
        } catch {
            onError((error as? APIError)?.message ?? error.localizedDescription)
        }
    }

    private func removeTag(_ tag: String) async {
        isSavingTags = true
        defer { isSavingTags = false }
        do {
            try await onTagsUpdated(tags.filter { $0 != tag })
        } catch {
            onError((error as? APIError)?.message ?? error.localizedDescription)
        }
    }

    private func saveDoNotService(_ flagged: Bool) async {
        isSavingFlag = true
        defer { isSavingFlag = false }
        do {
            try await onDoNotServiceUpdated(flagged)
        } catch {
            onError((error as? APIError)?.message ?? error.localizedDescription)
        }
    }
}

private struct FlowLayoutTags: View {
    let tags: [String]
    var onRemove: ((String) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.caption.weight(.medium))
                        if let onRemove {
                            Button {
                                onRemove(tag)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(StormTheme.ice.opacity(0.55))
                    .clipShape(Capsule())
                }
            }
        }
    }
}
