import SwiftUI

struct VisitChecklistsSection: View {
    let checklists: [ChecklistDTO]
    let onSaveItem: (String, String, JSONValue) async -> Void
    let onComplete: (String) async -> Void

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                StormSectionHeader(title: "Checklists", systemImage: "checklist")
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

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Notes", systemImage: "note.text")
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        if let author = note.author {
                            Text(author.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(StormTheme.sky)
                        }
                        Text(note.body)
                        Text(APIDateFormatting.displayString(from: note.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                HStack {
                    TextField("Add note…", text: $newNote, axis: .vertical)
                        .lineLimit(2...4)
                    Button("Add") { Task { await onAdd() } }
                        .buttonStyle(StormSecondaryButtonStyle())
                        .disabled(newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                            Text("Qty \(item.quantity, format: .number) × \(item.unitPrice, format: .currency(code: "USD"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.total, format: .currency(code: "USD"))
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
