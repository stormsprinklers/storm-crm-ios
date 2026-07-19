import SwiftUI

enum IrrigationMapSizing {
    /// Prefer a large, nearly square map that fills the phone width.
    static func preferredHeight(forWidth width: CGFloat, minimum: CGFloat = 320, maximum: CGFloat = 560) -> CGFloat {
        let proposed = width * 0.95
        return min(maximum, max(minimum, proposed))
    }
}

private struct ZoomableMapContainer<Content: View>: View {
    let height: CGFloat
    @ViewBuilder let content: () -> Content

    @State private var scale: CGFloat = 1
    @State private var steadyScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let base = content()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(scale)
                .offset(offset)
                // Pinch should not block parent ScrollView taps/pans.
                .simultaneousGesture(zoomGesture)
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        resetZoom()
                    }
                }
                .accessibilityHint("Pinch to zoom. Double-tap to reset.")

            // Only attach pan while zoomed so an always-on DragGesture cannot steal scrolls.
            if scale > 1.01 {
                base.simultaneousGesture(panGesture)
            } else {
                base
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(steadyScale * value, 1), 6)
            }
            .onEnded { _ in
                steadyScale = scale
                if scale <= 1.01 {
                    resetZoom(animated: true)
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
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
}

struct IrrigationMapCanvas: View {
    let imageUrl: String?
    let zones: [IrrigationMapZoneDTO]
    let markers: [IrrigationMapMarkerDTO]
    var maxHeight: CGFloat? = nil
    var allowsZoom: Bool = true
    /// When true (default), crop/zoom to drawn zones so the map isn't tiny/zoomed-out.
    var focusOnZones: Bool = true

    @State private var naturalImageSize = CGSize(width: 4, height: 3)

    private var focus: MapFocusRect? {
        guard focusOnZones else { return nil }
        return PolygonGeometry.mapFocusBounds(
            polygons: zones.map { $0.polygon },
            markerPoints: markers.map { $0.point }
        )
    }

    var body: some View {
        GeometryReader { geo in
            let height = maxHeight ?? IrrigationMapSizing.preferredHeight(forWidth: geo.size.width)
            Group {
                if allowsZoom {
                    ZoomableMapContainer(height: height) { mapContent }
                } else {
                    mapContent
                        .frame(width: geo.size.width, height: height)
                }
            }
            .frame(width: geo.size.width, height: height)
        }
        .frame(maxWidth: .infinity)
        .frame(height: maxHeight ?? IrrigationMapSizing.preferredHeight(forWidth: UIScreen.main.bounds.width - 32))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(StormTheme.ice, lineWidth: 1)
        )
    }

    private var mapContent: some View {
        GeometryReader { geometry in
            let layout = MapImageLayout(
                containerSize: geometry.size,
                imageSize: naturalImageSize,
                focus: focus
            )
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
                    placeholder("No aerial image on file")
                }

                Canvas { context, canvasSize in
                    let drawLayout = MapImageLayout(
                        containerSize: canvasSize,
                        imageSize: naturalImageSize,
                        focus: focus
                    )
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
            .clipped()
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
