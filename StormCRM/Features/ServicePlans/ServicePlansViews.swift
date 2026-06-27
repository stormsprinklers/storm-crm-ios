import SwiftUI

enum ServicePlanStatusStyle {
    static func badgeStyle(for status: String) -> StormBadge.Style {
        switch status {
        case "ACTIVE", "PENDING_RENEWAL":
            return .success
        case "DRAFT", "SENT":
            return .accent
        case "EXPIRING_SOON", "CANCELLED", "EXPIRED":
            return .warning
        default:
            return .neutral
        }
    }
}

struct CustomerServicePlansSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let customerId: String
    let properties: [CustomerPropertyDTO]
    let userRole: String

    @State private var enrollments: [MaintenanceEnrollmentDTO] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var showEnroll = false
    @State private var detailEnrollmentId: String?

    private var canManage: Bool { UserRoles.canManageEnrollments(userRole) }
    private var canView: Bool { UserRoles.canViewMaintenancePlans(userRole) }
    private var activePlans: [MaintenanceEnrollmentDTO] {
        enrollments.filter(\.isActivePlan)
    }

    var body: some View {
        Group {
            if canView {
                StormCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            StormSectionHeader(title: "Service plans", systemImage: "shield.lefthalf.filled")
                            Spacer()
                            if canManage {
                                Button("Enroll") { showEnroll = true }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(StormTheme.coral)
                            }
                        }

                        if activePlans.isEmpty && enrollments.filter({ $0.canAccept }).isEmpty {
                            Text("Not on a service plan")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }

                        if isLoading && enrollments.isEmpty {
                            ProgressView()
                        } else {
                            ForEach(enrollments) { enrollment in
                                Button {
                                    detailEnrollmentId = enrollment.id
                                } label: {
                                    EnrollmentRow(enrollment: enrollment)
                                }
                                .buttonStyle(.plain)
                                if enrollment.id != enrollments.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .sheet(isPresented: $showEnroll) {
                    NavigationStack {
                        EnrollServicePlanView(
                            customerId: customerId,
                            properties: properties
                        ) { enrollmentId in
                            showEnroll = false
                            detailEnrollmentId = enrollmentId
                            Task { await load() }
                        }
                    }
                }
                .sheet(isPresented: Binding(
                    get: { detailEnrollmentId != nil },
                    set: { if !$0 { detailEnrollmentId = nil } }
                )) {
                    if let enrollmentId = detailEnrollmentId {
                        NavigationStack {
                            ServicePlanEnrollmentDetailView(
                                enrollmentId: enrollmentId,
                                userRole: userRole,
                                onUpdated: { Task { await load() } }
                            )
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { detailEnrollmentId = nil }
                                }
                            }
                        }
                    }
                }
                .task { await load() }
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let response: MaintenanceEnrollmentsListResponse = try await env.apiClient.get(
                path: APIPath.maintenancePlanEnrollments,
                query: [URLQueryItem(name: "customerId", value: customerId)]
            )
            enrollments = response.enrollments
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct EnrollmentRow: View {
    let enrollment: MaintenanceEnrollmentDTO

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(enrollment.template.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(StormTheme.navy)
                Text(enrollment.property.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(ServicePlanFormatting.billingFrequencyLabel(enrollment.billingFrequency)) · \(ServicePlanFormatting.currency(enrollment.template.basePrice))/yr")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enrollment.canAccept {
                    Text("Pending activation — tap to review")
                        .font(.caption2)
                        .foregroundStyle(StormTheme.coral)
                }
            }
            Spacer()
            StormBadge(
                text: ServicePlanFormatting.statusLabel(enrollment.status),
                style: ServicePlanStatusStyle.badgeStyle(for: enrollment.status)
            )
        }
        .padding(.vertical, 2)
    }
}

struct EnrollServicePlanView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let customerId: String
    let properties: [CustomerPropertyDTO]
    var defaultPropertyId: String?
    let onEnrolled: (String) -> Void

    @State private var templates: [MaintenancePlanTemplateDTO] = []
    @State private var propertyId = ""
    @State private var templateId = ""
    @State private var billingFrequency = "ANNUAL"
    @State private var startDate = Date()
    @State private var autoRenew = true
    @State private var selectedAddonIds: Set<String> = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var error: String?

    private var selectedTemplate: MaintenancePlanTemplateDTO? {
        templates.first { $0.id == templateId }
    }

    var body: some View {
        Form {
            Section("Property") {
                if properties.isEmpty {
                    Text("This customer has no properties. Add a property on the web CRM first.")
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
                    Text("No active service plan templates. Create plans in CRM → Maintenance Plans.")
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
                    if let benefits = template.benefits, !benefits.isEmpty {
                        ForEach(benefits, id: \.self) { benefit in
                            Label(benefit, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(StormTheme.success)
                        }
                    }
                }
            }

            if selectedTemplate != nil {
                Section("Billing") {
                    Picker("Frequency", selection: $billingFrequency) {
                        ForEach(selectedTemplate?.allowedBillingFrequencies ?? ["ANNUAL"], id: \.self) { freq in
                            Text(ServicePlanFormatting.billingFrequencyLabel(freq)).tag(freq)
                        }
                    }
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    Toggle("Auto-renew", isOn: $autoRenew)
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
                Button("Create") { Task { await submit() } }
                    .disabled(isSaving || propertyId.isEmpty || templateId.isEmpty || properties.isEmpty)
            }
        }
        .task { await loadTemplates() }
        .onChange(of: templateId) { _, newValue in
            guard let template = templates.first(where: { $0.id == newValue }) else { return }
            billingFrequency = template.allowedBillingFrequencies.first ?? "ANNUAL"
            autoRenew = template.autoRenewDefault
            selectedAddonIds = []
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
            if templateId.isEmpty {
                templateId = templates.first?.id ?? ""
            }
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func submit() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        let body = CreateMaintenanceEnrollmentBody(
            customerId: customerId,
            propertyId: propertyId,
            templateId: templateId,
            billingFrequency: billingFrequency,
            startDate: APIDateFormatting.queryString(from: startDate),
            autoRenew: autoRenew,
            selectedAddonIds: Array(selectedAddonIds)
        )
        do {
            let enrollment: MaintenanceEnrollmentDTO = try await env.apiClient.post(
                path: APIPath.maintenancePlanEnrollments,
                body: body
            )
            onEnrolled(enrollment.id)
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct ServicePlanEnrollmentDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    let enrollmentId: String
    let userRole: String
    let onUpdated: () -> Void

    @State private var enrollment: MaintenanceEnrollmentDTO?
    @State private var error: String?
    @State private var isLoading = false
    @State private var isActivating = false

    private var canManage: Bool { UserRoles.canManageEnrollments(userRole) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let enrollment {
                    StormCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(enrollment.template.name)
                                        .font(.title3.weight(.semibold))
                                    Text("\(enrollment.customer.name) · \(enrollment.property.name)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StormBadge(
                                    text: ServicePlanFormatting.statusLabel(enrollment.status),
                                    style: ServicePlanStatusStyle.badgeStyle(for: enrollment.status)
                                )
                            }

                            LabeledContent("Billing") {
                                Text(ServicePlanFormatting.billingFrequencyLabel(enrollment.billingFrequency))
                            }
                            LabeledContent("Annual price") {
                                Text(ServicePlanFormatting.currency(enrollment.template.basePrice))
                            }
                            LabeledContent("Start date") {
                                Text(APIDateFormatting.displayString(from: enrollment.startDate))
                            }
                            if let nextBilling = enrollment.nextBillingDate {
                                LabeledContent("Next billing") {
                                    Text(APIDateFormatting.displayString(from: nextBilling))
                                }
                            }
                            LabeledContent("Auto-renew") {
                                Text(enrollment.autoRenew ? "Yes" : "No")
                            }

                            if canManage && enrollment.canAccept {
                                Button(isActivating ? "Activating…" : "Accept & activate plan") {
                                    Task { await acceptEnrollment() }
                                }
                                .buttonStyle(StormPrimaryButtonStyle())
                                .disabled(isActivating)
                                Text("Use after the customer agrees to the plan terms. This activates visits and billing.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let visits = enrollment.planVisits, !visits.isEmpty {
                        StormCard {
                            VStack(alignment: .leading, spacing: 8) {
                                StormSectionHeader(title: "Plan visits", systemImage: "calendar")
                                ForEach(visits) { visit in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(visit.visitTemplate?.visitTitle ?? visit.visitTemplate?.name ?? "Maintenance visit")
                                                .font(.subheadline)
                                            Text(ServicePlanFormatting.monthYear(visit.dueMonth, visit.dueYear))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        StormBadge(text: visit.status)
                                    }
                                    if visit.id != visits.last?.id { Divider() }
                                }
                            }
                        }
                    }

                    if let periods = enrollment.billingPeriods, !periods.isEmpty {
                        StormCard {
                            VStack(alignment: .leading, spacing: 8) {
                                StormSectionHeader(title: "Billing", systemImage: "dollarsign.circle")
                                ForEach(periods) { period in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text("\(APIDateFormatting.displayString(from: period.periodStart)) – \(APIDateFormatting.displayString(from: period.periodEnd))")
                                                .font(.caption)
                                            Text("Due \(APIDateFormatting.displayString(from: period.dueDate))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing) {
                                            Text(ServicePlanFormatting.currency(period.amount))
                                                .font(.subheadline.weight(.medium))
                                            StormBadge(text: period.status)
                                        }
                                    }
                                    if period.id != periods.last?.id { Divider() }
                                }
                            }
                        }
                    }
                } else if isLoading {
                    ProgressView("Loading plan…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }

                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .padding()
        }
        .background(StormTheme.page.ignoresSafeArea())
        .navigationTitle("Service plan")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            enrollment = try await env.apiClient.get(path: APIPath.maintenancePlanEnrollment(enrollmentId))
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func acceptEnrollment() async {
        isActivating = true
        defer { isActivating = false }
        do {
            enrollment = try await env.apiClient.post(
                path: APIPath.maintenancePlanEnrollmentAccept(enrollmentId)
            )
            onUpdated()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
