import SwiftUI

struct IrrigationMapEditorCanvas: View {
    let imageUrl: String?
    let zones: [EditableIrrigationZone]
    let markers: [EditableMapMarker]
    let activeZoneIndex: Int
    let draftPoints: ImagePolygon
    let readOnly: Bool
    var height: CGFloat = 420
    var onTap: ((ImagePoint) -> Void)?

    @State private var naturalImageSize = CGSize(width: 4, height: 3)
    @State private var scale: CGFloat = 1
    @State private var steadyScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let layout = MapImageLayout(containerSize: geometry.size, imageSize: naturalImageSize)
            ZStack(alignment: .topLeading) {
                if let imageUrl {
                    AuthenticatedBlobImage(urlString: imageUrl, contentMode: .fill) { size in
                        if size.width > 0, size.height > 0 {
                            naturalImageSize = size
                        }
                    }
                    .frame(width: layout.displayRect.width, height: layout.displayRect.height)
                    .position(x: layout.displayRect.midX, y: layout.displayRect.midY)
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
            .scaleEffect(scale)
            .offset(offset)
            .clipped()
            .contentShape(Rectangle())
            .highPriorityGesture(tapPlaceGesture(layout: layout))
            .gesture(zoomGesture)
            .simultaneousGesture(panGesture)
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) { resetZoom() }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(StormTheme.ice, lineWidth: 1)
        )
        .accessibilityHint("Tap to place points. Tap the first point to close. Pinch to zoom. Double-tap to reset zoom.")
    }

    private func tapPlaceGesture(layout: MapImageLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                // Ignore pans used for zoomed navigation
                guard !readOnly, let onTap else { return }
                guard hypot(value.translation.width, value.translation.height) < 8 else { return }
                // Convert from scaled/offset space back to layout coordinates
                let location = untransformed(value.location, in: layout.containerSize)
                guard let point = layout.normalizedPoint(from: location) else { return }
                onTap(point)
            }
    }

    private func untransformed(_ location: CGPoint, in size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let translated = CGPoint(
            x: location.x - offset.width - center.x,
            y: location.y - offset.height - center.y
        )
        return CGPoint(
            x: translated.x / scale + center.x,
            y: translated.y / scale + center.y
        )
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(steadyScale * value, 1), 6)
            }
            .onEnded { _ in
                steadyScale = scale
                if scale <= 1.01 { resetZoom(animated: true) }
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: steadyOffset.width + value.translation.width,
                    height: steadyOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                steadyOffset = offset
            }
    }

    private func resetZoom(animated: Bool = false) {
        let apply = {
            scale = 1
            steadyScale = 1
            offset = .zero
            steadyOffset = .zero
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) { apply() }
        } else {
            apply()
        }
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
        let canClose = draftPoints.count >= 3
        var path = Path()
        if let first = draftPoints.first {
            path.move(to: layout.cgPoint(from: first))
            for point in draftPoints.dropFirst() {
                path.addLine(to: layout.cgPoint(from: point))
            }
            if canClose {
                // Preview the closing edge back to the origin.
                path.addLine(to: layout.cgPoint(from: first))
            }
        }
        context.stroke(path, with: .color(StormTheme.coral), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        for (index, point) in draftPoints.enumerated() {
            let center = layout.cgPoint(from: point)
            let isOrigin = index == 0
            let radius: CGFloat = (isOrigin && canClose) ? 9 : 5
            let dot = Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.fill(dot, with: .color(StormTheme.coral))
            if isOrigin && canClose {
                let ring = Path(ellipseIn: CGRect(
                    x: center.x - 14,
                    y: center.y - 14,
                    width: 28,
                    height: 28
                ))
                context.stroke(ring, with: .color(StormTheme.coral), lineWidth: 2)
            }
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
