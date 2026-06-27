import CoreGraphics
import Foundation

struct ImagePoint: Equatable {
    var x: Double
    var y: Double
}

typealias ImagePolygon = [ImagePoint]

enum PolygonGeometry {
    static let zoneColors = [
        "#22c55e", "#3b82f6", "#f59e0b", "#ec4899",
        "#8b5cf6", "#14b8a6", "#ef4444", "#6366f1",
    ]

    static func polygon(from geo: JSONValue?) -> ImagePolygon? {
        guard case .object(let root) = geo else { return nil }
        guard case .array(let rings)? = root["coordinates"],
              let firstRing = rings.first,
              case .array(let ringPoints) = firstRing else { return nil }
        return ringPointsToPolygon(ringPoints)
    }

    static func point(from geo: JSONValue?) -> ImagePoint? {
        guard case .object(let root) = geo else { return nil }
        guard case .array(let coords) = root["coordinates"],
              coords.count >= 2,
              case .number(let x) = coords[0],
              case .number(let y) = coords[1] else { return nil }
        return ImagePoint(x: x, y: y)
    }

    static func polygonToGeoJson(_ polygon: ImagePolygon?) -> JSONValue {
        guard let polygon, polygon.count >= 3 else {
            return .object(["type": .string("Polygon"), "coordinates": .array([])])
        }
        var ring: [JSONValue] = polygon.map { point in
            .array([.number(point.x), .number(point.y)])
        }
        if let first = polygon.first {
            ring.append(.array([.number(first.x), .number(first.y)]))
        }
        return .object([
            "type": .string("Polygon"),
            "coordinates": .array([.array(ring)]),
        ])
    }

    static func pointToGeoJson(_ point: ImagePoint?) -> JSONValue {
        guard let point else {
            return .object(["type": .string("Point"), "coordinates": .array([])])
        }
        return .object([
            "type": .string("Point"),
            "coordinates": .array([.number(point.x), .number(point.y)]),
        ])
    }

    static func path(for polygon: ImagePolygon, in size: CGSize) -> CGPath {
        let path = CGMutablePath()
        guard let first = polygon.first else { return path }
        path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
        for point in polygon.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        path.closeSubpath()
        return path
    }

    static func zoneColor(index: Int) -> String {
        zoneColors[index % zoneColors.count]
    }

    static func centroid(_ polygon: ImagePolygon) -> ImagePoint {
        let sum = polygon.reduce(ImagePoint(x: 0, y: 0)) { acc, p in
            ImagePoint(x: acc.x + p.x, y: acc.y + p.y)
        }
        return ImagePoint(x: sum.x / Double(polygon.count), y: sum.y / Double(polygon.count))
    }

    static func roundNormalized(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    private static func ringPointsToPolygon(_ ringPoints: [JSONValue]) -> ImagePolygon? {
        var points: ImagePolygon = []
        for point in ringPoints {
            guard case .array(let pair) = point,
                  pair.count >= 2,
                  case .number(let x) = pair[0],
                  case .number(let y) = pair[1] else { continue }
            points.append(ImagePoint(x: x, y: y))
        }
        guard points.count >= 3 else { return nil }
        if let first = points.first, let last = points.last,
           first.x == last.x, first.y == last.y {
            points.removeLast()
        }
        return points.count >= 3 ? points : nil
    }
}

struct MapImageLayout {
    let containerSize: CGSize
    let imageSize: CGSize

    var displayRect: CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = (containerSize.width - width) / 2
        let y = (containerSize.height - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    func normalizedPoint(from location: CGPoint) -> ImagePoint? {
        let rect = displayRect
        guard rect.width > 0, rect.height > 0, rect.contains(location) else { return nil }
        let x = PolygonGeometry.roundNormalized(Double((location.x - rect.minX) / rect.width))
        let y = PolygonGeometry.roundNormalized(Double((location.y - rect.minY) / rect.height))
        guard x >= 0, x <= 1, y >= 0, y <= 1 else { return nil }
        return (x: x, y: y)
    }

    func cgPoint(from normalized: ImagePoint) -> CGPoint {
        let rect = displayRect
        return CGPoint(
            x: rect.minX + normalized.x * rect.width,
            y: rect.minY + normalized.y * rect.height
        )
    }
}
