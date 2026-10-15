import Foundation

/// Keep each card inside its actual interval, with a small gap before the next one.
enum ScheduleTimelineGeometry {
    static func block(start: Double, end: Double, visibleMinutes: Double, hourHeight: Double, padding: Double) -> (y: Double, height: Double) {
        let first = min(max(start, 0), visibleMinutes)
        let last = min(max(end, first), visibleMinutes)
        let available = max(0, (last - first) / 60 * hourHeight)
        return (padding + first / 60 * hourHeight, max(0, available - min(3, available)))
    }
}
