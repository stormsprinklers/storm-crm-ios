import SwiftUI

struct TimeTrackingBar: View {
    let visit: VisitDetailDTO
    let timeEvents: [TimeEventDTO]
    let onAction: (String) async -> Void

    @State private var now = Date()

    private var events: [TimeEventDTO] {
        timeEvents.sorted {
            let left = APIDateFormatting.parse($0.occurredAt) ?? .distantPast
            let right = APIDateFormatting.parse($1.occurredAt) ?? .distantPast
            return left < right
        }
    }

    private var status: String { visit.status }
    private var isPaused: Bool { status == "PAUSED" }
    private var isWorking: Bool { status == "IN_PROGRESS" }
    private var isEnRoute: Bool { status == "EN_ROUTE" }
    private var isCompleted: Bool { status == "COMPLETED" || status == "CANCELLED" }
    private var canFinish: Bool { ["IN_PROGRESS", "PAUSED", "EN_ROUTE"].contains(status) }
    private var workStarted: Bool { VisitTimeTrackingLogic.hasWorkStarted(events: events) }

    private var enRouteEvent: TimeEventDTO? {
        VisitTimeTrackingLogic.latestEvent(in: events, type: "EN_ROUTE")
    }

    private var startEvent: TimeEventDTO? {
        VisitTimeTrackingLogic.firstEvent(in: events, type: "START")
    }

    private var pauseEvent: TimeEventDTO? {
        VisitTimeTrackingLogic.latestEvent(in: events, type: "PAUSE")
    }

    private var finishEvent: TimeEventDTO? {
        VisitTimeTrackingLogic.latestEvent(in: events, type: "FINISH")
    }

    private var tickActive: Bool { isEnRoute || isWorking }

    private var onTheJobSeconds: Int {
        VisitTimeTrackingLogic.computeWorkSeconds(
            events: events,
            now: now,
            includeOpenSegment: isWorking
        )
    }

    private var enRouteSeconds: Int? {
        guard isEnRoute else { return nil }
        return VisitTimeTrackingLogic.computeEnRouteSeconds(
            events: events,
            status: status,
            now: now
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if workStarted || isWorking || isPaused || (isCompleted && startEvent != nil) {
                HStack {
                    Text("On-the-job time")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(StormTheme.navy)
                    Spacer()
                    Text(VisitTimeTrackingLogic.formatDuration(totalSeconds: onTheJobSeconds))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(StormTheme.navy)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(StormTheme.ice.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if isEnRoute, let eta = visit.eta?.formatted {
                Text("ETA: \(eta)")
                    .font(.subheadline)
                    .foregroundStyle(StormTheme.sky)
            }

            // Equal-width columns — no horizontal scroll on phone widths.
            HStack(alignment: .top, spacing: 6) {
                timeStep(
                    label: "On my way",
                    systemImage: "car.fill",
                    isActive: isEnRoute,
                    activeTint: StormTheme.sky,
                    counter: enRouteSeconds.map(VisitTimeTrackingLogic.formatDuration(totalSeconds:)),
                    timestamp: enRouteEvent?.occurredAt,
                    timestampLabel: enRouteEvent == nil ? nil : "Left at",
                    disabled: isCompleted || workStarted,
                    action: "EN_ROUTE"
                )

                if isPaused {
                    timeStep(
                        label: "Resume",
                        systemImage: "play.fill",
                        isActive: true,
                        activeTint: .orange,
                        counter: VisitTimeTrackingLogic.formatDuration(totalSeconds: onTheJobSeconds),
                        timestamp: startEvent?.occurredAt,
                        timestampLabel: startEvent == nil ? nil : "Started at",
                        secondaryTimestamp: pauseEvent?.occurredAt,
                        secondaryTimestampLabel: pauseEvent == nil ? nil : "Paused at",
                        disabled: isCompleted,
                        action: "RESUME"
                    )
                } else {
                timeStep(
                    label: isWorking ? "Pause" : "Start",
                    accessibilityLabel: isWorking ? "Pause" : "Start my time",
                    systemImage: isWorking ? "pause.fill" : "play.fill",
                    isActive: isWorking,
                    activeTint: StormTheme.success,
                    counter: (isWorking || workStarted)
                        ? VisitTimeTrackingLogic.formatDuration(totalSeconds: onTheJobSeconds)
                        : nil,
                    timestamp: startEvent?.occurredAt,
                    timestampLabel: startEvent == nil ? nil : "Started at",
                    disabled: isCompleted,
                    action: isWorking ? "PAUSE" : "START"
                )
                }

                timeStep(
                    label: "Finish",
                    accessibilityLabel: "Finish visit",
                    systemImage: "checkmark.square.fill",
                    isActive: isCompleted && finishEvent != nil,
                    activeTint: StormTheme.coral,
                    timestamp: finishEvent?.occurredAt,
                    timestampLabel: finishEvent == nil ? nil : "Finished at",
                    disabled: !canFinish,
                    action: "FINISH"
                )
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            guard tickActive else { return }
            now = date
        }
        .onChange(of: tickActive) { _, active in
            if active { now = Date() }
        }
    }

    @ViewBuilder
    private func timeStep(
        label: String,
        accessibilityLabel: String? = nil,
        systemImage: String,
        isActive: Bool,
        activeTint: Color,
        counter: String? = nil,
        timestamp: String?,
        timestampLabel: String?,
        secondaryTimestamp: String? = nil,
        secondaryTimestampLabel: String? = nil,
        disabled: Bool,
        action: String
    ) -> some View {
        VStack(spacing: 6) {
            Button {
                Task { await onAction(action) }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                .padding(.vertical, 10)
            }
            .buttonStyle(TimeTrackingStepButtonStyle(isActive: isActive, activeTint: activeTint))
            .disabled(disabled)
            .accessibilityLabel(accessibilityLabel ?? label)

            if let counter {
                Text(counter)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(StormTheme.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if let timestamp, let formatted = VisitTimeTrackingLogic.formatEventTimestamp(timestamp) {
                Text("\(timestampLabel ?? "At") \(formatted)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            if let secondaryTimestamp,
               let formatted = VisitTimeTrackingLogic.formatEventTimestamp(secondaryTimestamp) {
                Text("\(secondaryTimestampLabel ?? "At") \(formatted)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TimeTrackingStepButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isActive: Bool
    let activeTint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? Color.white : StormTheme.navy)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? activeTint.opacity(configuration.isPressed ? 0.85 : 1) : StormTheme.ice.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(activeTint, lineWidth: 2)
                        .padding(-2)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
}
