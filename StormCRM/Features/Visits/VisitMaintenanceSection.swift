import SwiftUI

struct VisitMaintenanceSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let visitId: String
    let userRole: String?
    var onUpdated: () async -> Void

    @State private var context: VisitMaintenanceContextDTO?
    @State private var properties: [CustomerPropertyDTO] = []
    @State private var selectedPlanVisitId: String = ""
    @State private var error: String?
    @State private var isLinking = false
    @State private var isLoading = true
    @State private var showEnroll = false
    @State private var detailEnrollmentId: String?

    private var canManage: Bool {
        guard let role = userRole else { return false }
        return UserRoles.canManageEnrollments(role)
    }

    private var canView: Bool {
        guard let role = userRole else { return false }
        return UserRoles.canViewMaintenancePlans(role)
    }

    private var hasActiveEnrollment: Bool {
        !(context?.enrollments?.isEmpty ?? true)
    }

    var body: some View {
        Group {
            if canView {
                StormCard {
                    VStack(alignment: .leading, spacing: 12) {
                        header

                        if isLoading && context == nil {
                            ProgressView()
                        } else if context?.customerId == nil {
                            Text("Assign a customer to this visit to view or sell maintenance plans.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let context {
                            content(for: context)
                        }

                        if let error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                .task { await load() }
                .sheet(isPresented: $showEnroll) {
                    if let customerId = context?.customerId {
                        NavigationStack {
                            EnrollMaintenancePlanFromVisitView(
                                visitId: visitId,
                                customerId: customerId,
                                properties: properties,
                                defaultPropertyId: context?.propertyId,
                                onChargeOnVisit: {
                                    showEnroll = false
                                    await load()
                                    await onUpdated()
                                },
                                onEnrolled: { enrollmentId in
                                    showEnroll = false
                                    detailEnrollmentId = enrollmentId
                                    Task {
                                        await load()
                                        await onUpdated()
                                    }
                                }
                            )
                        }
                    }
                }
                .sheet(isPresented: Binding(
                    get: { detailEnrollmentId != nil },
                    set: { if !$0 { detailEnrollmentId = nil } }
                )) {
                    if let enrollmentId = detailEnrollmentId, let role = userRole {
                        NavigationStack {
                            ServicePlanEnrollmentDetailView(
                                enrollmentId: enrollmentId,
                                userRole: role,
                                onUpdated: {
                                    Task {
                                        await load()
                                        await onUpdated()
                                    }
                                }
                            )
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { detailEnrollmentId = nil }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top) {
            StormSectionHeader(title: "Maintenance plan", systemImage: "shield.lefthalf.filled")
            Spacer(minLength: 8)
            if canManage, context?.customerId != nil, context?.linked == nil, !hasActiveEnrollment {
                Button {
                    Task { await prepareEnroll() }
                } label: {
                    Label("Enroll", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(StormSecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func content(for context: VisitMaintenanceContextDTO) -> some View {
        if let linked = context.linked {
            linkedPlanContent(linked)
        } else {
            if hasActiveEnrollment, let enrollments = context.enrollments {
                activeEnrollmentsContent(enrollments)
            } else {
                Text("Not on a maintenance plan\(context.propertyId != nil ? " for this property" : "").")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if canManage, let assignable = context.assignablePlanVisits, !assignable.isEmpty {
                assignPlanVisitContent(assignable)
            } else if hasActiveEnrollment, context.assignablePlanVisits?.isEmpty == true {
                Text("All included plan visits are already scheduled or completed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func linkedPlanContent(_ linked: LinkedPlanVisitDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StormBadge(text: "On plan", style: .success)
                StormBadge(text: ServicePlanFormatting.statusLabel(linked.status), style: .accent)
            }
            Text(linked.visitTitle)
                .font(.subheadline.weight(.semibold))
            Text("Due \(ServicePlanFormatting.monthYear(linked.dueMonth, linked.dueYear))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let enrollment = linked.enrollment {
                VStack(alignment: .leading, spacing: 4) {
                    if let name = enrollment.templateName {
                        enrollmentButton(id: enrollment.id, title: name)
                    }
                    if let propertyName = enrollment.propertyName {
                        Text(propertyName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StormTheme.ice.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func activeEnrollmentsContent(_ enrollments: [EnrollmentSummaryDTO]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active plan\(enrollments.count == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))
                .foregroundStyle(StormTheme.success)
            ForEach(enrollments) { enrollment in
                Button {
                    detailEnrollmentId = enrollment.id
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(enrollment.templateName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(StormTheme.navy)
                            Spacer()
                            StormBadge(
                                text: ServicePlanFormatting.statusLabel(enrollment.status),
                                style: ServicePlanStatusStyle.badgeStyle(for: enrollment.status)
                            )
                        }
                        Text(enrollment.propertyName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let freq = enrollment.billingFrequency, let price = enrollment.basePrice {
                            Text("\(ServicePlanFormatting.billingFrequencyLabel(freq)) · \(ServicePlanFormatting.currency(price))/yr")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let count = enrollment.unscheduledVisitCount, count > 0 {
                            Text("\(count) visit\(count == 1 ? "" : "s") ready to assign")
                                .font(.caption2)
                                .foregroundStyle(StormTheme.sky)
                        }
                    }
                    .padding(10)
                    .background(StormTheme.ice.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func assignPlanVisitContent(_ assignable: [AssignablePlanVisitDTO]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assign plan visit to this job")
                .font(.caption.weight(.semibold))
            Text("Link an included visit from their active plan. Plan discounts apply automatically.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Picker("Plan visit", selection: $selectedPlanVisitId) {
                ForEach(assignable) { planVisit in
                    Text("\(planVisit.visitTitle) · \(ServicePlanFormatting.monthYear(planVisit.dueMonth, planVisit.dueYear))")
                        .tag(planVisit.id)
                }
            }
            Button(isLinking ? "Assigning…" : "Assign to this visit") {
                Task { await linkPlanVisit() }
            }
            .buttonStyle(StormPrimaryButtonStyle())
            .disabled(isLinking || selectedPlanVisitId.isEmpty)
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(StormTheme.sky.opacity(0.5))
        )
    }

    @ViewBuilder
    private func enrollmentButton(id: String?, title: String) -> some View {
        if let id {
            Button {
                detailEnrollmentId = id
            } label: {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(StormTheme.sky)
            }
            .buttonStyle(.plain)
        } else {
            Text(title)
                .font(.subheadline.weight(.medium))
        }
    }

    private func load() async {
        guard canView else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            context = try await env.apiClient.get(path: APIPath.visitMaintenancePlan(visitId))
            if selectedPlanVisitId.isEmpty {
                selectedPlanVisitId = context?.assignablePlanVisits?.first?.id ?? ""
            }
            if let customerId = context?.customerId, properties.isEmpty {
                properties = try await env.apiClient.get(path: APIPath.customerProperties(customerId))
            }
            error = nil
        } catch {
            self.error = (error as? APIError)?.message
        }
    }

    private func prepareEnroll() async {
        guard let customerId = context?.customerId else { return }
        if properties.isEmpty {
            do {
                properties = try await env.apiClient.get(path: APIPath.customerProperties(customerId))
            } catch {
                self.error = (error as? APIError)?.message
                return
            }
        }
        if properties.isEmpty {
            error = "Add a property on the customer profile before enrolling in a plan."
            return
        }
        showEnroll = true
    }

    private func linkPlanVisit() async {
        isLinking = true
        defer { isLinking = false }
        struct Body: Encodable { let planVisitId: String }
        do {
            context = try await env.apiClient.post(
                path: APIPath.visitMaintenancePlan(visitId),
                body: Body(planVisitId: selectedPlanVisitId)
            )
            await onUpdated()
        } catch {
            self.error = (error as? APIError)?.message
        }
    }
}
