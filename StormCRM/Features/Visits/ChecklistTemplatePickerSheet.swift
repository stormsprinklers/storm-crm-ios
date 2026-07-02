import SwiftUI

struct ChecklistTemplatePickerSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let assignedTemplateIds: Set<String>
    let userRole: String?
    let onSelect: (ChecklistTemplateDTO) async -> Void

    @State private var templates: [ChecklistTemplateDTO] = []
    @State private var isLoading = false
    @State private var isAssigning = false
    @State private var error: String?

    private var availableTemplates: [ChecklistTemplateDTO] {
        templates.filter { template in
            template.active != false && !assignedTemplateIds.contains(template.id)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let error, templates.isEmpty {
                    ContentUnavailableView {
                        Label("Could not load checklists", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    }
                } else if availableTemplates.isEmpty, !isLoading {
                    ContentUnavailableView {
                        Label("No checklists available", systemImage: "checklist")
                    } description: {
                        Text(emptyMessage)
                    }
                } else {
                    List(availableTemplates) { template in
                        Button {
                            Task { await assign(template) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name)
                                    .foregroundStyle(StormTheme.navy)
                                if let description = template.description, !description.isEmpty {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if template.requiredForCompletion == true {
                                    Text("Required for job completion")
                                        .font(.caption2)
                                        .foregroundStyle(StormTheme.coral)
                                }
                            }
                        }
                        .disabled(isAssigning)
                    }
                }
            }
            .overlay {
                if isLoading || isAssigning {
                    ProgressView()
                }
            }
            .navigationTitle("Add checklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isAssigning)
                }
            }
            .task { await load() }
        }
    }

    private var emptyMessage: String {
        if templates.isEmpty {
            return "No checklist templates are available for your account."
        }
        return "Every available checklist is already on this visit."
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        let paths: [String]
        if let userRole, UserRoles.canManageChecklists(userRole) {
            paths = [APIPath.checklistTemplates, APIPath.settingsChecklists]
        } else {
            paths = [APIPath.checklistTemplates]
        }

        var lastError: String?
        for path in paths {
            do {
                let loaded: [ChecklistTemplateDTO] = try await env.apiClient.get(path: path)
                templates = loaded
                error = nil
                return
            } catch {
                lastError = (error as? APIError)?.message ?? error.localizedDescription
            }
        }

        templates = []
        error = lastError
    }

    private func assign(_ template: ChecklistTemplateDTO) async {
        isAssigning = true
        defer { isAssigning = false }
        await onSelect(template)
        dismiss()
    }
}
