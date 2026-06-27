import SwiftUI

struct IrrigationMapCanvas: View {
    let imageUrl: String?
    let zones: [IrrigationMapZoneDTO]
    let markers: [IrrigationMapMarkerDTO]
    var maxHeight: CGFloat = 360

    @State private var naturalImageSize = CGSize(width: 4, height: 3)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let imageUrl {
                    AuthenticatedBlobImage(urlString: imageUrl, contentMode: .fit) { size in
                        if size.width > 0, size.height > 0 {
                            naturalImageSize = size
                        }
                    }
                } else {
                    placeholder("No aerial image on file")
                }

                Canvas { context, canvasSize in
                    let drawLayout = MapImageLayout(containerSize: canvasSize, imageSize: naturalImageSize)
                    for (index, zone) in zones.enumerated() {
                        guard let polygon = zone.polygon, polygon.count >= 3 else { continue }
                        let path = polygonPath(polygon, layout: drawLayout)
                        let color = Color(hex: PolygonGeometry.zoneColor(index: index)) ?? StormTheme.sky
                        context.fill(path, with: .color(color.opacity(0.35)))
                        context.stroke(path, with: .color(color), lineWidth: 2)

                        let centroid = PolygonGeometry.centroid(polygon)
                        let labelPoint = drawLayout.cgPoint(from: centroid)
                        context.draw(
                            Text(zone.name).font(.caption2.bold()).foregroundColor(.white),
                            at: labelPoint,
                            anchor: .center
                        )
                    }

                    for marker in markers {
                        guard let point = marker.point else { continue }
                        let style = IrrigationConstants.markerStyle(for: marker.type)
                        let center = drawLayout.cgPoint(from: point)
                        let dot = Path(ellipseIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16))
                        context.fill(dot, with: .color(Color(hex: style.color) ?? StormTheme.navy))
                        context.draw(
                            Text(style.short).font(.caption2.bold()).foregroundColor(.white),
                            at: center,
                            anchor: .center
                        )
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(maxWidth: .infinity)
        .frame(height: maxHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(StormTheme.ice, lineWidth: 1)
        )
    }

    private func placeholder(_ text: String) -> some View {
        ZStack {
            StormTheme.ice.opacity(0.3)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
    }

    private func polygonPath(_ polygon: ImagePolygon, layout: MapImageLayout) -> Path {
        var path = Path()
        guard let first = polygon.first else { return path }
        path.move(to: layout.cgPoint(from: first))
        for point in polygon.dropFirst() {
            path.addLine(to: layout.cgPoint(from: point))
        }
        path.closeSubpath()
        return path
    }
}

struct IrrigationZoneLegend: View {
    let zones: [IrrigationMapZoneDTO]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: PolygonGeometry.zoneColor(index: index)) ?? StormTheme.sky)
                        .frame(width: 10, height: 10)
                    Text(zone.name).font(.subheadline)
                    if let type = zone.irrigationType {
                        Text(type.replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let gpm = zone.estimatedGpm {
                        Text(String(format: "%.1f GPM", gpm))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
