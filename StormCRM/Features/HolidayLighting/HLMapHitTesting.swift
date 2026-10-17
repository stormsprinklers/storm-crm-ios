import Foundation

/// Screen-space segment hit testing stays consistent at every map zoom level.
enum HLMapHitTesting {
    static func distance(_ point: CGPoint, to start: CGPoint, end: CGPoint) -> Double {
        let dx = end.x - start.x, dy = end.y - start.y
        let squared = dx * dx + dy * dy
        guard squared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / squared))
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }
}
