import SwiftUI

struct IrrigationMapEditorCanvas: View {
    let imageUrl: String?
    let zones: [EditableIrrigationZone]
    let markers: [EditableMapMarker]
    let activeZoneIndex: Int
    let draftPoints: ImagePolygon
    let readOnly: Bool
    var maxHeight: CGFloat = 400
    var onTap: ((ImagePoint) -> Void)?

    @State private var naturalImageSize = CGSize(width: 4, height: 3)

    var body: some View {
        GeometryReader { geometry in
            let layout = MapImageLayout(containerSize: geometry.size, imageSize: naturalImageSize)
            ZStack {
                if let imageUrl {
                    AuthenticatedBlobImage(urlString: imageUrl, contentMode: .fit) { size in
                        if size.width > 0, size.height > 0 {
                            naturalImageSize = size
                        }
                    }
                } else {
                    placeholder("Capture an aerial image to draw zones")
                }

                Canvas { context, canvasSize in
                    let drawLayout = MapImageLayout(containerSize: canvasSize, imageSize: naturalImageSize)
                    drawZones(context: &context, layout: drawLayout)
                    drawDraft(context: &context, layout: drawLayout)
                    drawMarkers(context: &context, layout: drawLayout)
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard !readOnly, let onTap,
                              let point = layout.normalizedPoint(from: value.location) else { return }
                        onTap(point)
                    }
            )
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

    private func drawZones(context: inout GraphicsContext, layout: MapImageLayout) {
        for (index, zone) in zones.enumerated() {
            guard let polygon = zone.polygon, polygon.count >= 3 else { continue }
            let path = polygonPath(polygon, layout: layout)
            let color = Color(hex: PolygonGeometry.zoneColor(index: index)) ?? StormTheme.sky
            let isActive = index == activeZoneIndex
            context.fill(path, with: .color(color.opacity(isActive ? 0.45 : 0.28)))
            context.stroke(path, with: .color(color), lineWidth: isActive ? 3 : 2)

            let centroid = PolygonGeometry.centroid(polygon)
            let labelPoint = layout.cgPoint(from: centroid)
            context.draw(
                Text(zone.name).font(.caption2.bold()).foregroundColor(.white),
                at: labelPoint,
                anchor: .center
            )
        }
    }

    private func drawDraft(context: inout GraphicsContext, layout: MapImageLayout) {
        guard !draftPoints.isEmpty else { return }
        var path = Path()
        if let first = draftPoints.first {
            path.move(to: layout.cgPoint(from: first))
            for point in draftPoints.dropFirst() {
                path.addLine(to: layout.cgPoint(from: point))
            }
        }
        context.stroke(path, with: .color(StormTheme.coral), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        for point in draftPoints {
            let center = layout.cgPoint(from: point)
            let dot = Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
            context.fill(dot, with: .color(StormTheme.coral))
        }
    }

    private func drawMarkers(context: inout GraphicsContext, layout: MapImageLayout) {
        for marker in markers {
            guard let point = marker.point else { continue }
            let style = IrrigationConstants.markerStyle(for: marker.type)
            let center = layout.cgPoint(from: point)
            let dot = Path(ellipseIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16))
            context.fill(dot, with: .color(Color(hex: style.color) ?? StormTheme.navy))
            context.draw(
                Text(style.short).font(.caption2.bold()).foregroundColor(.white),
                at: center,
                anchor: .center
            )
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
