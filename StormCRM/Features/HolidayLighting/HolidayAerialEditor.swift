import SwiftUI
import MapKit

struct HolidayAerialEditor: View {
    @ObservedObject var model: HolidayQuoteViewModel
    var embedded = false
    @State private var distance = 80.0
    @State private var mapCenter: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic
    @State private var mode = "move"
    @State private var draft: [HLPoint] = []
    private let colors: [Color] = [.orange, .cyan, .pink, .green, .purple, .yellow]
    var body: some View {
        VStack(spacing: 0) {
            Picker("Map tool", selection: $mode) {
                Text("Move").tag("move"); Text("Roofline").tag("draw"); Text("Tree").tag("tree"); Text("Bush").tag("bush")
            }.pickerStyle(.segmented).padding()
            MapReader { proxy in
                Map(position: $camera, bounds: MapCameraBounds(minimumDistance: 1, maximumDistance: 100_000), interactionModes: [.pan, .zoom, .rotate]) {
                    ForEach(Array(model.active.measurements.segments.enumerated()), id: \.element.id) { index, segment in
                        MapPolyline(coordinates: segment.path.map(\.coordinate)).stroke(colors[index % colors.count], lineWidth: 5)
                        if let point = segment.path.first {
                            Annotation(segment.label, coordinate: point.coordinate) { Text(segment.label).font(.caption2.bold()).padding(4).background(.regularMaterial, in: Capsule()) }
                        }
                    }
                    ForEach(model.active.measurements.placements) { placement in
                        Annotation(placement.label, coordinate: placement.point.coordinate) {
                            VStack(spacing: 2) { Image(systemName: placement.kind == "tree" ? "tree.fill" : "leaf.fill").foregroundStyle(.green); Text(placement.label).font(.caption2) }.padding(4).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    if !draft.isEmpty {
                        MapPolyline(coordinates: draft.map(\.coordinate)).stroke(.yellow, style: StrokeStyle(lineWidth: 4, dash: [6, 4]))
                        ForEach(Array(draft.enumerated()), id: \.offset) { index, point in
                            Annotation("Point \(index + 1)", coordinate: point.coordinate) { Circle().fill(.yellow).frame(width: 10, height: 10) }
                        }
                    }
                }
                .onMapCameraChange { context in distance = context.camera.distance; mapCenter = context.camera.centerCoordinate }
                .overlay(alignment: .topTrailing) { VStack { Button { zoom(0.5) } label: { Image(systemName: "plus.magnifyingglass") }; Button { zoom(2) } label: { Image(systemName: "minus.magnifyingglass") } }.buttonStyle(.bordered).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) }
                .mapStyle(.imagery(elevation: .flat))
                .mapControls { MapCompass(); MapScaleView() }
                .onTapGesture { location in
                    guard mode != "move", let coordinate = proxy.convert(location, from: .local) else { return }
                    let point = HLPoint(coordinate)
                    if mode == "draw" { draft.append(point) }
                    else {
                        model.edit { option in
                            let count = option.measurements.placements.filter { $0.kind == mode }.count + 1
                            option.measurements.placements.append(HLPlacement(kind: mode, point: point, color: option.selections.color, count: count))
                        }
                    }
                }
            }
            if mode == "draw" {
                HStack {
                    Button("Undo point") { if !draft.isEmpty { draft.removeLast() } }.disabled(draft.isEmpty)
                    Spacer()
                    Text("\(HLPoint.lengthFeet(draft), specifier: "%.1f") ft").monospacedDigit()
                    Spacer()
                    Button("Finish run") {
                        model.edit { option in option.measurements.segments.append(HLSegment(path: draft, style: option.selections.style, color: option.selections.color, count: option.measurements.segments.count + 1)) }
                        draft = []
                    }.disabled(draft.count < 2)
                }.font(.subheadline).padding().background(.regularMaterial)
            }
            NavigationLink("Manual Measurements") { HLMeasurementList(model: model) }.padding()
        }
        .onAppear { focus() }
        .onChange(of: model.center) { _, _ in focus() }

        .onChange(of: mode) { _, next in if next != "draw" { draft = [] } }
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
