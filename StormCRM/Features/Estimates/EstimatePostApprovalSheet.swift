import SwiftUI

/// After estimate signature approval: today vs another day, schedule, and deposit collection.
struct EstimatePostApprovalSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let estimateId: String
    let estimateTotal: Double
    let linkedVisitId: String?
    let optionId: String?
    let sourceVisit: VisitDetailDTO?
    var onFinished: () async -> Void

    private enum Step {
        case timing
        case schedule
        case deposit
    }

    @State private var step: Step = .timing
    @State private var isSaving = false
    @State private var error: String?
    @State private var startDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var endDate = Calendar.current.date(byAdding: .hour, value: 26, to: Date()) ?? Date()
    @State private var threshold: Double = 1000
    @State private var percent: Double = 50
    @State private var resultVisitId: String?
    @State private var depositDue: Double = 0
    @State private var showPayment = false

    private var previewDeposit: Double {
        guard estimateTotal > threshold else { return 0 }
        return (estimateTotal * (percent / 100) * 100).rounded() / 100
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .timing:
                    timingStep
                case .schedule:
                    scheduleStep
                case .deposit:
                    depositStep
                }
            }
            .padding()
            .background(StormTheme.page.ignoresSafeArea())
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .timing ? "Close" : "Back") {
                        if step == .timing || step == .deposit {
                            dismiss()
                        } else {
                            step = .timing
                            error = nil
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .task { await loadDepositSettings() }
            .sheet(isPresented: $showPayment) {
                if let resultVisitId {
                    PaymentSheet(visitId: resultVisitId, amountDue: depositDue) {
                        Task {
                            await onFinished()
                            showPayment = false
                            dismiss()
                        }
                    }
                    .environmentObject(env)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var navTitle: String {
        switch step {
        case .timing: return "Schedule work"
        case .schedule: return "Another day"
        case .deposit: return "Collect deposit"
        }
    }

    private var timingStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Are you completing this work today, or another day?")
                .font(.title3.weight(.semibold))
                .foregroundStyle(StormTheme.navy)

            Text("Estimate total: \(estimateTotal.formatted(.currency(code: "USD")))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Button {
                Task { await submit(timing: "today") }
            } label: {
                Label(isSaving ? "Saving…" : "Completing today", systemImage: "sun.max.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StormPrimaryButtonStyle())
            .disabled(isSaving)

            Button {
                error = nil
                step = .schedule
            } label: {
                Label("Another day", systemImage: "calendar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StormSecondaryButtonStyle())
            .disabled(isSaving)

            Spacer(minLength: 0)
        }
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a day and time for this work.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            DatePicker("Start", selection: $startDate)
            DatePicker("End", selection: $endDate)

            VStack(alignment: .leading, spacing: 6) {
                if previewDeposit > 0 {
                    Text("Deposit due: \(previewDeposit.formatted(.currency(code: "USD")))")
                        .font(.headline)
                        .foregroundStyle(StormTheme.navy)
                    Text(
                        "Totals over \(threshold.formatted(.currency(code: "USD"))) require a \(Int(percent))% deposit when booking for another day."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("No deposit required")
                        .font(.headline)
                        .foregroundStyle(StormTheme.navy)
                    Text(
                        "This visit is at or under the \(threshold.formatted(.currency(code: "USD"))) threshold."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StormTheme.ice.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Button {
                Task { await submit(timing: "another_day") }
            } label: {
                Label(isSaving ? "Scheduling…" : "Schedule visit", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StormPrimaryButtonStyle())
            .disabled(isSaving || endDate <= startDate)

            Spacer(minLength: 0)
        }
    }

    private var depositStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Visit scheduled")
                .font(.title3.weight(.semibold))
                .foregroundStyle(StormTheme.navy)

            Text(
                "Collect \(depositDue.formatted(.currency(code: "USD"))) now (\(Int(percent))% of \(estimateTotal.formatted(.currency(code: "USD"))))."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Button {
                showPayment = true
            } label: {
                Label("Collect deposit", systemImage: "creditcard.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StormPrimaryButtonStyle())

            Button {
                Task {
                    await onFinished()
                    dismiss()
                }
            } label: {
                Text("Skip for now")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StormSecondaryButtonStyle())

            Spacer(minLength: 0)
        }
    }

    private func loadDepositSettings() async {
        struct SettingsDTO: Decodable {
            let deferredVisitDepositThreshold: Double?
            let deferredVisitDepositPercent: Double?

            enum CodingKeys: String, CodingKey {
                case deferredVisitDepositThreshold, deferredVisitDepositPercent
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                deferredVisitDepositThreshold = try c.decodeFlexibleDouble(forKey: .deferredVisitDepositThreshold)
                deferredVisitDepositPercent = try c.decodeFlexibleDouble(forKey: .deferredVisitDepositPercent)
            }
        }
        do {
            let settings: SettingsDTO = try await env.apiClient.get(path: APIPath.estimateSettings)
            if let t = settings.deferredVisitDepositThreshold { threshold = t }
            if let p = settings.deferredVisitDepositPercent { percent = p }
        } catch {
            // Keep defaults (1000 / 50%).
        }
    }

    private func submit(timing: String) async {
        isSaving = true
        error = nil
        defer { isSaving = false }

        struct ScheduleBody: Encodable {
            let title: String
            let startAt: String
            let endAt: String
            let division: String
            let zip: String?
            let serviceAreaId: String?
            let assignedUserId: String?
            let address: String?
            let city: String?
            let state: String?
        }
        struct Body: Encodable {
            let timing: String
            let visitId: String?
            let optionId: String?
            let schedule: ScheduleBody?
        }

        let schedule: ScheduleBody? = timing == "another_day"
            ? ScheduleBody(
                title: "Work from estimate",
                startAt: VisitDateEditing.isoString(from: startDate),
                endAt: VisitDateEditing.isoString(from: endDate),
                division: sourceVisit?.division ?? "SERVICE",
                zip: sourceVisit?.zip ?? sourceVisit?.property?.zip,
                serviceAreaId: sourceVisit?.serviceArea?.id,
                assignedUserId: sourceVisit?.assignedUser?.id,
                address: sourceVisit?.address ?? sourceVisit?.property?.address,
                city: sourceVisit?.city ?? sourceVisit?.property?.city,
                state: sourceVisit?.state ?? sourceVisit?.property?.state
            )
            : nil

        let body = Body(
            timing: timing,
            visitId: linkedVisitId,
            optionId: optionId,
            schedule: schedule
        )

        do {
            let response: EstimatePostApprovalResponse = try await env.apiClient.post(
                path: APIPath.estimatePostApproval(estimateId),
                body: body
            )
            resultVisitId = response.visitId
            depositDue = response.depositDue
            await onFinished()

            if timing == "today" {
                dismiss()
                return
            }

            if response.depositDue > 0 {
                step = .deposit
            } else {
                dismiss()
            }
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct EstimatePostApprovalResponse: Decodable {
    let visitId: String
    let estimateId: String
    let depositDue: Double
    let depositRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case visitId, estimateId, depositDue, depositRequired
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        visitId = try c.decode(String.self, forKey: .visitId)
        estimateId = try c.decode(String.self, forKey: .estimateId)
        depositDue = try c.decodeFlexibleDouble(forKey: .depositDue) ?? 0
        depositRequired = try c.decodeIfPresent(Bool.self, forKey: .depositRequired)
    }
}
