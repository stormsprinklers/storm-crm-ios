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

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    StormSectionHeader(title: "Service plan", systemImage: "shield.lefthalf.filled")
                    Spacer()
                    if canManage, context?.customerId != nil {
                        Button("Sell plan") { showEnroll = true }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(StormTheme.coral)
                    }
                }

                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else if let context {
                    if let linked = context.linked {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Linked to plan visit")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(StormTheme.success)
                            Text(linked.visitTitle).font(.subheadline.bold())
                            Text(ServicePlanFormatting.monthYear(linked.dueMonth, linked.dueYear))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let enrollment = linked.enrollment {
                                Text("\(enrollment.templateName ?? "Plan") · \(enrollment.propertyName ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if canManage, let assignable = context.assignablePlanVisits, !assignable.isEmpty {
                        Text("Assign this visit to a plan visit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Plan visit", selection: $selectedPlanVisitId) {
                            ForEach(assignable) { planVisit in
                                Text("\(planVisit.visitTitle) · \(ServicePlanFormatting.monthYear(planVisit.dueMonth, planVisit.dueYear))")
                                    .tag(planVisit.id)
                            }
                        }
                        Button(isLinking ? "Linking…" : "Link to plan visit") {
                            Task { await linkPlanVisit() }
                        }
                        .buttonStyle(StormPrimaryButtonStyle())
                        .disabled(isLinking || selectedPlanVisitId.isEmpty)
                    } else if let enrollments = context.enrollments, !enrollments.isEmpty {
                        Text("Active service plans").font(.caption.bold())
                        ForEach(enrollments) { enrollment in
                            Button {
                                detailEnrollmentId = enrollment.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(enrollment.templateName).font(.subheadline)
                                        Text(enrollment.propertyName).font(.caption).foregroundStyle(.secondary)
                                        if let freq = enrollment.billingFrequency,
                                           let price = enrollment.basePrice {
                                            Text("\(ServicePlanFormatting.billingFrequencyLabel(freq)) · \(ServicePlanFormatting.currency(price))/yr")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                    StormBadge(
                                        text: ServicePlanFormatting.statusLabel(enrollment.status),
                                        style: ServicePlanStatusStyle.badgeStyle(for: enrollment.status)
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Text("Customer is not on a service plan for this property.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showEnroll) {
            if let customerId = context?.customerId {
                NavigationStack {
                    EnrollServicePlanView(
                        customerId: customerId,
                        properties: properties,
                        defaultPropertyId: context?.propertyId
                    ) { enrollmentId in
                        showEnroll = false
                        detailEnrollmentId = enrollmentId
                        Task {
                            await load()
                            await onUpdated()
                        }
                    }
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

    private func load() async {
        guard canView else { return }
        do {
            context = try await env.apiClient.get(path: APIPath.visitMaintenancePlan(visitId))
            if selectedPlanVisitId.isEmpty {
                selectedPlanVisitId = context?.assignablePlanVisits?.first?.id ?? ""
            }
            if let customerId = context?.customerId, properties.isEmpty {
                properties = try await env.apiClient.get(path: APIPath.customerProperties(customerId))
            }
        } catch {
            self.error = (error as? APIError)?.message
        }
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
