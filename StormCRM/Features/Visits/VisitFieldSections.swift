import SwiftUI

struct VisitChecklistsSection: View {
    let checklists: [ChecklistDTO]
    let onToggle: (String, String, Bool) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Checklists").font(.headline)
            if checklists.isEmpty {
                Text("No checklists").foregroundStyle(.secondary)
            } else {
                ForEach(checklists) { checklist in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(checklist.name).font(.subheadline.bold())
                        ForEach(checklist.items) { item in
                            Toggle(isOn: Binding(
                                get: { item.isCompleted },
                                set: { newValue in
                                    Task { await onToggle(checklist.id, item.id, newValue) }
                                }
                            )) {
                                Text(item.label)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct VisitNotesSection: View {
    let notes: [VisitNoteDTO]
    @Binding var newNote: String
    let onAdd: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes").font(.headline)
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.body)
                    Text(note.createdAt).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            HStack {
                TextField("Add note…", text: $newNote, axis: .vertical)
                    .lineLimit(2...4)
                Button("Add") { Task { await onAdd() } }
                    .disabled(newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct LineItemsSection: View {
    let items: [LineItemDTO]
    let total: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Line items").font(.headline)
            ForEach(items) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.name)
                        Text("Qty \(item.quantity, format: .number)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.total, format: .currency(code: "USD"))
                }
            }
            if let total {
                Divider()
                HStack {
                    Text("Total").bold()
                    Spacer()
                    Text(total, format: .currency(code: "USD")).bold()
                }
            }
        }
    }
}
