import Foundation

enum VisitTimeTrackingLogic {
    static func latestEvent(in events: [TimeEventDTO], type: String) -> TimeEventDTO? {
        events.last { $0.type == type }
    }

    static func firstEvent(in events: [TimeEventDTO], type: String) -> TimeEventDTO? {
        events.first { $0.type == type }
    }

    static func formatDuration(totalSeconds: Int) -> String {
        let safe = max(0, totalSeconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let seconds = safe % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func formatEventTimestamp(_ iso: String) -> String? {
        guard let date = APIDateFormatting.parse(iso) else { return nil }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    static func computeWorkSeconds(
        events: [TimeEventDTO],
        now: Date,
        includeOpenSegment: Bool
    ) -> Int {
        var workMs: Double = 0
        var segmentStart: Date?

        for event in events {
            guard let at = APIDateFormatting.parse(event.occurredAt) else { continue }
            if event.type == "START" || event.type == "RESUME" {
                segmentStart = at
            }
            if (event.type == "PAUSE" || event.type == "FINISH"), let start = segmentStart {
                workMs += at.timeIntervalSince(start) * 1000
                segmentStart = nil
            }
        }

        if includeOpenSegment, let start = segmentStart {
            workMs += now.timeIntervalSince(start) * 1000
        }

        return Int(workMs / 1000)
    }

    static func computeEnRouteSeconds(
        events: [TimeEventDTO],
        status: String,
        now: Date
    ) -> Int {
        guard let enRouteEvent = latestEvent(in: events, type: "EN_ROUTE"),
              let enRouteAt = APIDateFormatting.parse(enRouteEvent.occurredAt)
        else { return 0 }

        var endedAt: Date?
        for event in events {
            guard let at = APIDateFormatting.parse(event.occurredAt), at > enRouteAt else { continue }
            if event.type == "START" || event.type == "RESUME" || event.type == "FINISH" {
                endedAt = at
                break
            }
        }

        if status == "EN_ROUTE", endedAt == nil {
            return Int(now.timeIntervalSince(enRouteAt))
        }
        if let endedAt {
            return Int(endedAt.timeIntervalSince(enRouteAt))
        }
        return 0
    }

    static func hasWorkStarted(events: [TimeEventDTO]) -> Bool {
        firstEvent(in: events, type: "START") != nil
    }
}
