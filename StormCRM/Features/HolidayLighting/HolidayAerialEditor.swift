import SwiftUI
import MapKit
import UIKit

struct HolidayAerialEditor: View {
    @ObservedObject var model: HolidayQuoteViewModel
    var embedded = false
    @State private var distance = 80.0
    @State private var mapCenter: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic
    @State private var mode = "draw"
    @State private var placementKind = "tree"
    @State private var selectedSegmentID: String?
    @State private var selectedPlacementID: String?
    @State private var draft: [HLPoint] = []
    @State private var showingManualMeasurements = false
    private let colors: [Color] = [.orange, .cyan, .pink, .green, .purple, .yellow]
    var body: some View {
        VStack(spacing: 0) {
            Picker("Map tool", selection: $mode) {
                Text("Strands").tag("draw"); Text("Trees / Bushes").tag("placement"); Text("Select").tag("select")
            }.pickerStyle(.segmented).padding()
            if mode == "placement" {
                Picker("Place", selection: $placementKind) {
                    Text("Tree").tag("tree")
                    Text("Bush").tag("bush")
                }.pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
            }
            MapReader { proxy in
                Map(position: $camera, bounds: MapCameraBounds(minimumDistance: 1, maximumDistance: 100_000), interactionModes: [.pan, .zoom, .rotate]) {
                    ForEach(Array(model.active.measurements.segments.enumerated()), id: \.element.id) { index, segment in
                        MapPolyline(coordinates: segment.path.map(\.coordinate)).stroke(colors[index % colors.count], lineWidth: selectedSegmentID == segment.id ? 9 : 5)
                        if let point = segment.path.first {
                            Annotation(segment.label, coordinate: point.coordinate) { Text(segment.label).font(.caption2.bold()).padding(4).background(selectedSegmentID == segment.id ? Color.yellow.opacity(0.9) : Color.white.opacity(0.9), in: Capsule()) }
                        }
                    }
                    ForEach(model.active.measurements.placements) { placement in
                        Annotation(placement.label, coordinate: placement.point.coordinate) {
                            VStack(spacing: 2) { Image(systemName: placement.kind == "tree" ? "tree.fill" : "leaf.fill").foregroundStyle(.green); Text(placement.label).font(.caption2) }.padding(4).background(selectedPlacementID == placement.id ? Color.yellow.opacity(0.9) : Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    if !draft.isEmpty {
                        MapPolyline(coordinates: draft.map(\.coordinate)).stroke(.yellow, style: StrokeStyle(lineWidth: 4, dash: [6, 4]))
                        ForEach(Array(draft.enumerated()), id: \.offset) { index, point in
                            Annotation("Point \(index + 1)", coordinate: point.coordinate) { Circle().fill(.yellow).frame(width: 10, height: 10) }
                        }
                    }
                }
                .background(HLTwoFingerMapPan())
                .onMapCameraChange { context in distance = context.camera.distance; mapCenter = context.camera.centerCoordinate }
                .overlay(alignment: .topTrailing) { VStack { Button { zoom(0.5) } label: { Image(systemName: "plus.magnifyingglass") }; Button { zoom(2) } label: { Image(systemName: "minus.magnifyingglass") } }.buttonStyle(.bordered).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) }
                .mapStyle(.imagery(elevation: .flat))
                .mapControls { MapCompass(); MapScaleView() }
                .onTapGesture { location in
                    guard let coordinate = proxy.convert(location, from: .local) else { return }
                    if mode == "select" {
                        selectItem(at: location, proxy: proxy)
                    } else if mode == "draw" {
                        selectedSegmentID = nil; selectedPlacementID = nil
                        draft.append(HLPoint(coordinate))
                    } else {
                        let placement = HLPlacement(
                            kind: placementKind, point: HLPoint(coordinate), color: model.active.selections.color,
                            count: model.active.measurements.placements.filter { $0.kind == placementKind }.count + 1
                        )
                        model.edit { $0.measurements.placements.append(placement) }
                        selectedSegmentID = nil; selectedPlacementID = placement.id
                    }
                }
            }.frame(height: 320)
            if mode == "draw" {
                HStack {
                    Button("Undo point") { if !draft.isEmpty { draft.removeLast() } }.disabled(draft.isEmpty)
                    Spacer()
                    Text("\(HLPoint.lengthFeet(draft), specifier: "%.1f") ft").monospacedDigit()
                    Spacer()
                    Button("Finish run") {
                        let segment = HLSegment(path: draft, style: model.active.selections.style, color: model.active.selections.color, count: model.active.measurements.segments.count + 1)
                        model.edit { $0.measurements.segments.append(segment) }
                        selectedSegmentID = segment.id; selectedPlacementID = nil
                        draft = []
                    }.disabled(draft.count < 2)
                }.font(.subheadline).padding().background(.regularMaterial)
            }
            selectionControls
            Button("Manual Measurements") { showingManualMeasurements = true }
                .buttonStyle(.borderless)
                .padding()
        }
        // A NavigationLink inside this composite Form row makes the entire map a link.
        .buttonStyle(.borderless)
        .sheet(isPresented: $showingManualMeasurements) {
            NavigationStack {
                HLMeasurementList(model: model)
                    .safeAreaInset(edge: .top) { HLPreviewProgress(model: model) }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingManualMeasurements = false }
                        }
                    }
            }
        }
        .onAppear { focus() }
        .onChange(of: model.center) { _, _ in focus() }

        .onChange(of: mode) { _, next in if next != "draw" { draft = [] } }
        .onChange(of: model.active.id) { _, _ in
            draft = []; selectedSegmentID = nil; selectedPlacementID = nil
        }
    }
    @ViewBuilder private var selectionControls: some View {
        if let id = selectedSegmentID, model.active.measurements.segments.contains(where: { $0.id == id }) {
            HLAerialSegmentControls(segment: model.segmentBinding(id)) {
                model.removeSegment(id); selectedSegmentID = nil
            }.padding().background(.regularMaterial)
        } else if let id = selectedPlacementID, model.active.measurements.placements.contains(where: { $0.id == id }) {
            HLAerialPlacementControls(placement: model.placementBinding(id)) {
                model.edit { $0.measurements.placements.removeAll { $0.id == id } }
                selectedPlacementID = nil
            }.padding().background(.regularMaterial)
        }
    }

    private func selectItem(at location: CGPoint, proxy: MapProxy) {
        var nearest = 28.0
        selectedSegmentID = nil; selectedPlacementID = nil
        for segment in model.active.measurements.segments {
            let points = segment.path.compactMap { proxy.convert($0.coordinate, to: .local) }
            let distances = zip(points, points.dropFirst()).map { HLMapHitTesting.distance(location, to: $0.0, end: $0.1) }
            let distance = distances.min() ?? points.first.map { hypot(location.x - $0.x, location.y - $0.y) } ?? .infinity
            if distance < nearest { nearest = distance; selectedSegmentID = segment.id }
        }
        for placement in model.active.measurements.placements {
            guard let point = proxy.convert(placement.point.coordinate, to: .local) else { continue }
            let distance = hypot(location.x - point.x, location.y - point.y)
            if distance < nearest { nearest = distance; selectedSegmentID = nil; selectedPlacementID = placement.id }
        }
    }

    private func zoom(_ factor: Double) {
        guard let center = mapCenter ?? model.center?.coordinate else { return }
        camera = .camera(MapCamera(centerCoordinate: center, distance: min(100_000, max(1, distance * factor)), heading: 0, pitch: 0))
    }
    private func focus() {
        if let point = model.center ?? model.active.measurements.segments.first?.path.first ?? model.active.measurements.placements.first?.point {
            camera = .camera(MapCamera(centerCoordinate: point.coordinate, distance: 80, heading: 0, pitch: 0))
        }
    }
}

private struct HLAerialSegmentControls: View {
    @Binding var segment: HLSegment
    let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(segment.label).font(.subheadline.bold()); Spacer(); Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.accessibilityLabel("Delete " + segment.label) }
            Toggle("Peak strand", isOn: $segment.hasPeak)
        }
    }
}

private struct HLAerialPlacementControls: View {
    @Binding var placement: HLPlacement
    let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(placement.label).font(.subheadline.bold()); Spacer(); Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.accessibilityLabel("Delete " + placement.label) }
            HStack {
                Text("Strand count")
                Spacer()
                TextField("Strands", value: $placement.strands, format: .number)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 70)
            }
            Picker("Difficulty", selection: $placement.difficulty) {
                Text("Standard").tag(1); Text("Moderate").tag(2); Text("Difficult").tag(3)
            }.pickerStyle(.segmented)
        }
    }
}

/// Configure MapKit's pan recognizers without changing pinch zoom or rotation.
private struct HLTwoFingerMapPan: UIViewRepresentable {
    func makeUIView(context: Context) -> PanConfigurationView { PanConfigurationView() }
    func updateUIView(_ uiView: PanConfigurationView, context: Context) { uiView.setNeedsLayout() }
    final class PanConfigurationView: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            var ancestor = superview
            for _ in 0..<6 {
                guard let view = ancestor else { break }
                if let map = findMap(in: view) {
                    configurePan(in: map)
                    return
                }
                ancestor = view.superview
            }
        }
        private func findMap(in view: UIView) -> MKMapView? {
            if let map = view as? MKMapView { return map }
            for child in view.subviews { if let map = findMap(in: child) { return map } }
            return nil
        }
        private func configurePan(in view: UIView) {
            for recognizer in view.gestureRecognizers ?? [] {
                if let pan = recognizer as? UIPanGestureRecognizer {
                    pan.minimumNumberOfTouches = 2
                }
            }
            for child in view.subviews { configurePan(in: child) }
        }
    }
}


struct HLMeasurementList: View {
    @ObservedObject var model: HolidayQuoteViewModel
    var body: some View {
        List {
            Section("Strands") {
                ForEach(model.active.measurements.segments) { segment in
                    HStack { NavigationLink { HLSegmentEditor(segment: model.segmentBinding(segment.id), catalog: model.catalog) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(segment.label)
                            Text("\(segment.length, specifier: "%.1f") ft · \(segment.style.uppercased()) · \(segment.color)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                        Button(role: .destructive) { model.removeSegment(segment.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel("Delete " + segment.label)
                    }
                }
                Button("Add strand") { model.edit { option in option.measurements.segments.append(HLSegment(path: [], style: option.selections.style, color: option.selections.color, count: option.measurements.segments.count + 1)) } }
            }
            Section("Trees and bushes") {
                ForEach(model.active.measurements.placements) { placement in
                    HStack { NavigationLink { HLPlacementEditor(placement: model.placementBinding(placement.id)) } label: {
                        VStack(alignment: .leading, spacing: 4) { Text(placement.label); Text("\(placement.strands) strands · difficulty \(placement.difficulty) · \(placement.color)").font(.caption).foregroundStyle(.secondary) }
                    }
                        Button(role: .destructive) { model.edit { $0.measurements.placements.removeAll { $0.id == placement.id } } } label: { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel("Delete " + placement.label)
                    }
                }
                ForEach(["tree", "bush"], id: \.self) { kind in
                    Button("Add " + kind) {
                        model.edit { option in option.measurements.placements.append(HLPlacement(kind: kind, point: model.center ?? HLPoint(lat: 0, lng: 0), color: option.selections.color, count: option.measurements.placements.filter { $0.kind == kind }.count + 1)) }
                    }
                }
            }
        }.navigationTitle("Manual Measurements").background(HLKeyboardDismissal())
    }
}
private struct HLSegmentEditor: View {
    @Binding var segment: HLSegment
    let catalog: HLCatalog?
    var body: some View {
        Form {
            Section("Run") {
                TextField("Run label", text: $segment.label)
                LabeledContent("Horizontal feet") { TextField("Feet", value: $segment.length, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            }
            Section("Lights") {
                Picker("Bulbs", selection: $segment.style) { ForEach(catalog?.lightStyles ?? []) { Text($0.label).tag($0.key) } }
                HLColorField(value: $segment.color)
            }
        }.navigationTitle(segment.label)
        .background(HLKeyboardDismissal())
    }
}
private struct HLPlacementEditor: View {
    @Binding var placement: HLPlacement
    var body: some View {
        Form {
            TextField("Label", text: $placement.label)
            LabeledContent("Strand count") { TextField("Strands", value: $placement.strands, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            Picker("Difficulty", selection: $placement.difficulty) { Text("1 — Standard").tag(1); Text("2 — Moderate").tag(2); Text("3 — Difficult").tag(3) }
            if placement.kind == "tree" { Toggle("Lift rental needed", isOn: $placement.lift) }
            LabeledContent("Bulb type", value: "Mini LEDs")
            HLColorField(value: $placement.color)
        }.navigationTitle(placement.label).background(HLKeyboardDismissal())
    }
}
