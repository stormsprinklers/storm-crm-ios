import SwiftUI

private enum MaintenancePlanPaymentSetup: String, CaseIterable, Identifiable {
    case chargeOnVisit
    case recurring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chargeOnVisit: return "Charge on this job"
        case .recurring: return "Set up recurring billing"
        }
    }

    var detail: String {
        switch self {
        case .chargeOnVisit:
            return "Adds the plan price as a line item on this visit."
        case .recurring:
            return "Creates an enrollment for ongoing plan billing."
        }
    }
}

struct EnrollMaintenancePlanFromVisitView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let visitId: String
    let customerId: String
    let properties: [CustomerPropertyDTO]
    var defaultPropertyId: String?
    let onChargeOnVisit: () async -> Void
    let onEnrolled: (String) -> Void

    @State private var templates: [MaintenancePlanTemplateDTO] = []
    @State private var propertyId = ""
    @State private var templateId = ""
    @State private var paymentSetup: MaintenancePlanPaymentSetup = .chargeOnVisit
    @State private var billingFrequency = "MONTHLY"
    @State private var startDate = Date()
    @State private var autoRenew = true
    @State private var selectedAddonIds: Set<String> = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var cardSetupURL: URL?

    private var selectedTemplate: MaintenancePlanTemplateDTO? {
        templates.first { $0.id == templateId }
    }

    private var chargeAmount: Double {
        guard let template = selectedTemplate else { return 0 }
        let addonTotal = template.activeAddons
            .filter { selectedAddonIds.contains($0.id) }
            .reduce(0) { $0 + $1.price }
        return template.basePrice + addonTotal
    }

    private var availableRecurringFrequencies: [String] {
        selectedTemplate?.allowedBillingFrequencies.filter { $0 != "MULTI_YEAR_UPFRONT" } ?? ["MONTHLY"]
    }

    var body: some View {
        Form {
            Section("Property") {
                if properties.isEmpty {
                    Text("Add a property on the customer profile before enrolling in a plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Property", selection: $propertyId) {
                        ForEach(properties) { property in
                            Text(property.name).tag(property.id)
                        }
                    }
                }
            }

            Section("Plan") {
                if templates.isEmpty && !isLoading {
                    Text("No active maintenance plan templates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Template", selection: $templateId) {
                        Text("Select plan").tag("")
                        ForEach(templates) { template in
                            Text("\(template.name) — \(ServicePlanFormatting.currency(template.basePrice))/yr")
                                .tag(template.id)
                        }
                    }
                }

                if let template = selectedTemplate {
                    if let description = template.description, !description.isEmpty {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if selectedTemplate != nil {
                Section("How to bill") {
                    Picker("Billing", selection: $paymentSetup) {
                        ForEach(MaintenancePlanPaymentSetup.allCases) { setup in
                            Text(setup.title).tag(setup)
                        }
                    }
                    .pickerStyle(.inline)

                    Text(paymentSetup.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if paymentSetup == .chargeOnVisit {
                        LabeledContent("Line item total") {
                            Text(chargeAmount, format: .currency(code: "USD"))
                                .font(.subheadline.weight(.semibold))
                        }
                    } else {
                        Picker("Frequency", selection: $billingFrequency) {
                            ForEach(availableRecurringFrequencies, id: \.self) { freq in
                                Text(ServicePlanFormatting.billingFrequencyLabel(freq)).tag(freq)
                            }
                        }
                        DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                        Toggle("Auto-renew", isOn: $autoRenew)
                    }
                }

                if let addons = selectedTemplate?.activeAddons, !addons.isEmpty {
                    Section("Add-ons") {
                        ForEach(addons) { addon in
                            Toggle(isOn: Binding(
                                get: { selectedAddonIds.contains(addon.id) },
                                set: { checked in
                                    if checked { selectedAddonIds.insert(addon.id) }
                                    else { selectedAddonIds.remove(addon.id) }
                                }
                            )) {
                                VStack(alignment: .leading) {
                                    Text(addon.name)
                                    Text("+\(ServicePlanFormatting.currency(addon.price))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            if let error {
                Section {
                    Text(error).foregroundStyle(.red).font(.caption)
                    if cardSetupURL != nil {
                        Button("Add card on file") {
                            if let url = cardSetupURL {
                                openURL(url)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Enroll in plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(paymentSetup == .chargeOnVisit ? "Add to job" : "Create enrollment") {
                    Task { await submit() }
                }
                .disabled(isSaving || propertyId.isEmpty || templateId.isEmpty || properties.isEmpty)
            }
        }
        .overlay {
            if isLoading || isSaving { ProgressView() }
        }
        .task { await loadTemplates() }
        .onChange(of: templateId) { _, newValue in
            guard let template = templates.first(where: { $0.id == newValue }) else { return }
            autoRenew = template.autoRenewDefault
            selectedAddonIds = []
            let recurring = template.allowedBillingFrequencies.first { $0 == "MONTHLY" }
                ?? template.allowedBillingFrequencies.first { $0 != "MULTI_YEAR_UPFRONT" }
                ?? template.allowedBillingFrequencies.first
                ?? "ANNUAL"
            billingFrequency = recurring
            if !template.allowedBillingFrequencies.contains("MONTHLY")
                && paymentSetup == .recurring
                && availableRecurringFrequencies.count == 1 {
                billingFrequency = availableRecurringFrequencies[0]
            }
        }
        .onChange(of: paymentSetup) { _, newValue in
            if newValue == .recurring, let template = selectedTemplate {
                if template.allowedBillingFrequencies.contains("MONTHLY") {
                    billingFrequency = "MONTHLY"
                } else if let first = availableRecurringFrequencies.first {
                    billingFrequency = first
                }
            }
        }
    }

    private func loadTemplates() async {
        isLoading = true
        defer { isLoading = false }
        propertyId = defaultPropertyId
            ?? properties.first(where: { $0.isPrimary == true })?.id
            ?? properties.first?.id
            ?? ""
        do {
            let response: MaintenancePlanTemplatesResponse = try await env.apiClient.get(
                path: APIPath.maintenancePlanTemplates
            )
            templates = response.templates.filter(\.active)
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func submit() async {
        guard let template = selectedTemplate else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }

        if paymentSetup == .chargeOnVisit {
            await chargeOnVisit(template: template)
        } else {
            await createEnrollment(template: template)
        }
    }

    private func chargeOnVisit(template: MaintenancePlanTemplateDTO) async {
        struct Body: Encodable {
            let name: String
            let description: String?
            let unitPrice: Double
            let quantity: Double
        }

        let addonNames = template.activeAddons
            .filter { selectedAddonIds.contains($0.id) }
            .map(\.name)
        var description = template.description
        if !addonNames.isEmpty {
            let addonText = "Includes: \(addonNames.joined(separator: ", "))"
            description = [description, addonText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        }

        do {
            let _: VisitDetailDTO = try await env.apiClient.post(
                path: APIPath.visitLineItems(visitId),
                body: Body(
                    name: template.name,
                    description: description,
                    unitPrice: chargeAmount,
                    quantity: 1
                )
            )
            await onChargeOnVisit()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func createEnrollment(template: MaintenancePlanTemplateDTO) async {
        let body = CreateMaintenanceEnrollmentBody(
            customerId: customerId,
            propertyId: propertyId,
            templateId: template.id,
            billingFrequency: billingFrequency,
            startDate: APIDateFormatting.queryString(from: startDate),
            autoRenew: autoRenew,
            selectedAddonIds: Array(selectedAddonIds)
        )
        do {
            cardSetupURL = nil
            let enrollment: MaintenanceEnrollmentDTO = try await env.apiClient.post(
                path: APIPath.maintenancePlanEnrollments,
                body: body
            )
            onEnrolled(enrollment.id)
            dismiss()
        } catch let apiError as APIError {
            if case .cardRequired(let message, let setupUrl) = apiError {
                error = message
                cardSetupURL = URL(string: setupUrl)
                if let url = cardSetupURL {
                    openURL(url)
                }
            } else {
                self.error = apiError.message
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
