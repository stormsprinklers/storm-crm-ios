import SwiftUI
import MapKit

struct HolidayAerialEditor: View {
    @ObservedObject var model: HolidayQuoteViewModel
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
                Map(position: $camera, interactionModes: [.pan, .zoom, .rotate]) {
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
        .navigationTitle("Aerial lighting plan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focus() }
        .onChange(of: model.center) { _, _ in focus() }
        .toolbar { Button("Center property", systemImage: "scope") { focus() } }
        .onChange(of: mode) { _, next in if next != "draw" { draft = [] } }
    }
    private func focus() {
        if let point = model.center ?? model.active.measurements.segments.first?.path.first ?? model.active.measurements.placements.first?.point {
            camera = .region(MKCoordinateRegion(center: point.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)))
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
            Stepper("\(placement.strands) strands", value: $placement.strands, in: 1...100)
            Picker("Difficulty", selection: $placement.difficulty) { Text("1 — Standard").tag(1); Text("2 — Moderate").tag(2); Text("3 — Difficult").tag(3) }
            if placement.kind == "tree" { Toggle("Lift rental needed", isOn: $placement.lift) }
            LabeledContent("Bulb type", value: "Mini LEDs")
            HLColorField(value: $placement.color)
        }.navigationTitle(placement.label).background(HLKeyboardDismissal())
    }
}
struct HLPricingFields: View {
    @ObservedObject var model: HolidayQuoteViewModel
    private var adjustment: HLAdjustment { model.active.selections.adjustments[model.active.selections.pricingMode] ?? HLAdjustment() }
    var body: some View {
        Group {
            Section("Parts and labor") {
                if model.active.selections.pricingMode != "labor" {
                    component("Parts price", get: { adjustment.partsPrice ?? model.pricing?.optionDetails[model.active.selections.pricingMode]?.partsPrice }, set: { value in change { $0.partsPrice = max(0, value); $0.price = nil } })
                }
                component("Labor price", get: { adjustment.laborPrice ?? model.pricing?.optionDetails[model.active.selections.pricingMode]?.laborPrice }, set: { value in change { $0.laborPrice = max(0, value); $0.price = nil } })
                if adjustment.partsPrice != nil || adjustment.laborPrice != nil || adjustment.price != nil {
                    Button("Reset prices") { change { $0.partsPrice = nil; $0.laborPrice = nil; $0.price = nil } }
                }
                TextField("Discount label", text: Binding(get: { adjustment.discountLabel ?? "" }, set: { value in change { $0.discountLabel = value } }))
                Picker("Discount type", selection: Binding(get: { adjustment.discountType ?? "fixed" }, set: { value in change { $0.discountType = value } })) { Text("Dollar amount").tag("fixed"); Text("Percent").tag("percent") }
                number("Discount", get: { adjustment.discountAmount ?? 0 }, set: { value in change { $0.discountAmount = max(0, value) } })
                Toggle("Override reinstall price", isOn: Binding(get: { model.active.selections.reinstallPrice != nil }, set: { enabled in model.edit(invalidatePreview: false) { $0.selections.reinstallPrice = enabled ? (model.pricing?.reinstallTotal ?? 0) : nil } }))
                if model.active.selections.reinstallPrice != nil { number("Reinstall price", get: { model.active.selections.reinstallPrice ?? 0 }, set: { value in model.edit(invalidatePreview: false) { $0.selections.reinstallPrice = max(0, value) } }) }
            }
            Section("Additional services") {
                ForEach(model.active.selections.services) { service in
                    NavigationLink { HLServiceEditor(service: model.serviceBinding(service.id)) } label: { Text(service.name.isEmpty ? "Unnamed service" : service.name) }
                        .swipeActions { Button("Delete", role: .destructive) { model.edit(invalidatePreview: false) { $0.selections.services.removeAll { $0.id == service.id } } } }
                }
                Button("Add service") { model.edit(invalidatePreview: false) { $0.selections.services.append(HLService()) } }
            }
        }
    }
    private func change(_ update: (inout HLAdjustment) -> Void) {
        model.edit(invalidatePreview: false) { option in var value = adjustment; update(&value); option.selections.adjustments[option.selections.pricingMode] = value }
    }
    private func component(_ label: String, get: @escaping () -> Double?, set: @escaping (Double) -> Void) -> some View {
        LabeledContent(label) { TextField("Calculate or enter price", value: Binding(get: get, set: { set($0 ?? 0) }), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
    }
    private func number(_ label: String, get: @escaping () -> Double, set: @escaping (Double) -> Void) -> some View {
        LabeledContent(label) { TextField(label, value: Binding(get: get, set: set), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
    }
}
private struct HLServiceEditor: View {
    @Binding var service: HLService
    var body: some View {
        Form {
            TextField("Service name", text: $service.name)
            TextField("Description", text: $service.detail, axis: .vertical)
            LabeledContent("Quantity") { TextField("Quantity", value: $service.quantity, format: .number).keyboardType(.decimalPad) }
            LabeledContent("Unit price") { TextField("Price", value: $service.unitPrice, format: .number).keyboardType(.decimalPad) }
        }.navigationTitle("Additional service").background(HLKeyboardDismissal())
    }
}
