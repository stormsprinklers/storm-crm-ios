import SwiftUI

struct VisitChecklistsSection: View {
    let checklists: [ChecklistDTO]
    var embedded: Bool = false
    let onSaveItem: (String, String, JSONValue) async -> Void
    let onComplete: (String) async -> Void

    var body: some View {
        Group {
            if embedded {
                checklistContent
            } else {
                StormCard { checklistContent }
            }
        }
    }

    @ViewBuilder
    private var checklistContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !embedded {
                StormSectionHeader(title: "Checklists", systemImage: "checklist")
            }
            if checklists.isEmpty {
                Text("No checklists").foregroundStyle(.secondary)
            } else {
                ForEach(checklists) { checklist in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(checklist.name).font(.subheadline.bold())
                                if checklist.completedAt != nil {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(StormTheme.success)
                                }
                                Spacer()
                                if let progress = checklist.progress {
                                    Text("\(progress.requiredComplete ?? 0)/\(progress.requiredTotal ?? 0) required")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            ForEach(checklist.items) { item in
                                ChecklistItemRow(item: item) { response in
                                    await onSaveItem(checklist.id, item.id, response)
                                }
                            }
                            if checklist.completedAt == nil {
                                Button("Mark checklist complete") {
                                    Task { await onComplete(checklist.id) }
                                }
                                .font(.caption)
                                .buttonStyle(StormSecondaryButtonStyle())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
        }
    }
}

private struct ChecklistItemRow: View {
    let item: ChecklistItemDTO
    let onSave: (JSONValue) async -> Void
    @State private var textResponse = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch item.type?.uppercased() {
            case "TEXT", "TEXTAREA", "SHORT_TEXT", "LONG_TEXT":
                Text(item.label).font(.subheadline)
                TextField("Response", text: $textResponse, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        if case .string(let value) = item.response {
                            textResponse = value
                        }
                    }
                Button("Save") {
                    Task { await onSave(.string(textResponse)) }
                }
                .font(.caption)
                .disabled(textResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case "NUMBER":
                Text(item.label).font(.subheadline)
                TextField("Number", text: $textResponse)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        if case .number(let value) = item.response {
                            textResponse = String(value)
                        }
                    }
                Button("Save") {
                    if let number = Double(textResponse) {
                        Task { await onSave(.number(number)) }
                    }
                }
                .font(.caption)
            default:
                Toggle(isOn: Binding(
                    get: { item.isCompleted },
                    set: { newValue in
                        Task { await onSave(.bool(newValue)) }
                    }
                )) {
                    Text(item.label)
                }
            }
            if let help = item.helpText, !help.isEmpty {
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct VisitNotesSection: View {
    let notes: [VisitNoteDTO]
    @Binding var newNote: String
    let onAdd: () async -> Void
    let onUpdate: (String, String) async throws -> Void
    let onDelete: (String) async throws -> Void

    @State private var editingNote: VisitNoteDTO?
    @State private var deletingNote: VisitNoteDTO?
    @State private var actionError: String?

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                StormSectionHeader(title: "Notes", systemImage: "note.text")

                if notes.isEmpty {
                    Text("No notes yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(notes) { note in
                        HStack(alignment: .top, spacing: 10) {
                            if let author = note.author {
                                EmployeeAvatar(person: author, size: 34)
                            } else {
                                Circle()
                                    .fill(StormTheme.ice)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .font(.caption)
                                            .foregroundStyle(StormTheme.navy.opacity(0.5))
                                    }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    if let author = note.author {
                                        Text(author.name)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(StormTheme.navy)
                                    }
                                    Text(APIDateFormatting.displayString(from: note.createdAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if !note.id.hasPrefix("offline-") {
                                        Menu {
                                            Button {
                                                editingNote = note
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            Button(role: .destructive) {
                                                deletingNote = note
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis")
                                                .frame(width: 28, height: 28)
                                        }
                                    }
                                }
                                Text(note.body)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding(.vertical, 4)

                        if note.id != notes.last?.id {
                            Divider()
                        }
                    }
                }

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Add note…", text: $newNote, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") { Task { await onAdd() } }
                        .buttonStyle(StormSecondaryButtonStyle())
                        .disabled(newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let actionError {
                    Text(actionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .sheet(item: $editingNote) { note in
            VisitNoteEditSheet(note: note) { body in
                do {
                    try await onUpdate(note.id, body)
                    editingNote = nil
                } catch {
                    actionError = (error as? APIError)?.message ?? error.localizedDescription
                }
            }
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(
                get: { deletingNote != nil },
                set: { if !$0 { deletingNote = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete note", role: .destructive) {
                guard let note = deletingNote else { return }
                deletingNote = nil
                Task {
                    do {
                        try await onDelete(note.id)
                    } catch {
                        actionError = (error as? APIError)?.message ?? error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) { deletingNote = nil }
        }
    }
}

private struct VisitNoteEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let note: VisitNoteDTO
    let onSave: (String) async -> Void

    @State private var noteBody: String
    @State private var saving = false

    init(note: VisitNoteDTO, onSave: @escaping (String) async -> Void) {
        self.note = note
        self.onSave = onSave
        _noteBody = State(initialValue: note.body)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $noteBody)
                    .frame(minHeight: 140)
            }
            .navigationTitle("Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        saving = true
                        Task {
                            await onSave(noteBody.trimmingCharacters(in: .whitespacesAndNewlines))
                            saving = false
                        }
                    }
                    .disabled(saving || noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct LineItemsSection: View {
    let items: [LineItemDTO]
    let discounts: [DiscountDTO]
    let subtotal: Double
    let discountTotal: Double
    let total: Double

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Line items", systemImage: "list.bullet")
                ForEach(items) { item in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            if let description = item.description, !description.isEmpty {
                                Text(description).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(item.qtyPriceLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.displayTotal, format: .currency(code: "USD"))
                    }
                    .padding(.vertical, 2)
                }
                if !discounts.isEmpty {
                    Divider()
                    ForEach(discounts) { discount in
                        HStack {
                            Text(discount.name)
                            Spacer()
                            Text("−\(discount.amount, format: .currency(code: "USD"))")
                                .foregroundStyle(StormTheme.coral)
                        }
                        .font(.subheadline)
                    }
                }
                Divider()
                HStack {
                    Text("Subtotal")
                    Spacer()
                    Text(subtotal, format: .currency(code: "USD"))
                }
                if discountTotal > 0 {
                    HStack {
                        Text("Discounts")
                        Spacer()
                        Text("−\(discountTotal, format: .currency(code: "USD"))")
                            .foregroundStyle(StormTheme.coral)
                    }
                }
                HStack {
                    Text("Total").bold()
                    Spacer()
                    Text(total, format: .currency(code: "USD")).bold()
                }
            }
        }
    }
}
