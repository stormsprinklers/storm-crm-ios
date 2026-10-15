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
            Text(instruction).font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.bottom, 8)
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
            NavigationLink("Edit measurements, peaks, bulbs and strands") { HLMeasurementList(model: model) }.padding()
        }
        .navigationTitle("Aerial lighting plan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focus() }
        .onChange(of: model.center) { _, _ in focus() }
        .toolbar { Button("Center property", systemImage: "scope") { focus() } }
        .onChange(of: mode) { _, next in if next != "draw" { draft = [] } }
    }
    private var instruction: String {
        switch mode {
        case "draw": return "Tap roof corners in order, then Finish run. Pan and pinch to adjust the aerial view."
        case "tree", "bush": return "Tap to place a \(mode). Set strand count, difficulty and colors in Measurements."
        default: return "Pan, pinch to zoom and rotate. Select Roofline to measure a run. Aerial measurements should be verified in the field."
        }
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
            Section("Roofline runs") {
                ForEach(model.active.measurements.segments) { segment in
                    NavigationLink { HLSegmentEditor(segment: model.segmentBinding(segment.id), catalog: model.catalog) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(segment.label)
                            Text("\(segment.length, specifier: "%.1f") ft\(segment.hasPeak ? " · peak × 1.5" : "") · \(segment.style.uppercased()) · \(segment.color)").font(.caption).foregroundStyle(.secondary)
                        }
                    }.swipeActions { Button("Delete", role: .destructive) { model.removeSegment(segment.id) } }
                }
                Button("Add manually measured run") { model.edit { option in option.measurements.segments.append(HLSegment(path: [], style: option.selections.style, color: option.selections.color, count: option.measurements.segments.count + 1)) } }
            }
            Section("Trees and bushes") {
                ForEach(model.active.measurements.placements) { placement in
                    NavigationLink { HLPlacementEditor(placement: model.placementBinding(placement.id)) } label: {
                        VStack(alignment: .leading, spacing: 4) { Text(placement.label); Text("\(placement.strands) strands · difficulty \(placement.difficulty) · \(placement.color)").font(.caption).foregroundStyle(.secondary) }
                    }.swipeActions { Button("Delete", role: .destructive) { model.edit { $0.measurements.placements.removeAll { $0.id == placement.id } } } }
                }
                Text("Place trees and bushes on the aerial plan.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Connected strands") {
                ForEach(model.active.measurements.strands) { strand in
                    NavigationLink { HLStrandEditor(model: model, id: strand.id) } label: { VStack(alignment: .leading) { Text(strand.label); Text("\(strand.segmentIDs.count) runs").font(.caption).foregroundStyle(.secondary) } }
                        .swipeActions { Button("Delete", role: .destructive) { model.edit { $0.measurements.strands.removeAll { $0.id == strand.id } } } }
                }
                Button("Add strand group") { model.edit { $0.measurements.strands.append(HLStrand(label: "Strand \($0.measurements.strands.count + 1)", segments: [])) } }
            }
        }.navigationTitle("Measurements")
    }
}
private struct HLSegmentEditor: View {
    @Binding var segment: HLSegment
    let catalog: HLCatalog?
    var body: some View {
        Form {
            Section("Run") {
                TextField("Run label", text: $segment.label)
                Picker("Kind", selection: $segment.kind) { Text("Roofline").tag("roofline"); Text("Peak").tag("peak"); Text("Garland").tag("garland"); Text("Custom").tag("custom") }
                LabeledContent("Horizontal feet") { TextField("Feet", value: $segment.length, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                Toggle("Has peak (1.5× horizontal feet)", isOn: $segment.hasPeak)
                Text("Billed run: \(segment.length * (segment.hasPeak ? 1.5 : 1), specifier: "%.1f") ft").font(.caption)
            }
            Section("Lights") {
                Picker("Bulbs", selection: $segment.style) { ForEach(catalog?.lightStyles ?? []) { Text($0.label).tag($0.key) } }
                HLColorField(value: $segment.color)
            }
        }.navigationTitle(segment.label)
        .onChange(of: segment.kind) { _, kind in if kind == "peak" { segment.hasPeak = true } }
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
        }.navigationTitle(placement.label)
    }
}
private struct HLStrandEditor: View {
    @ObservedObject var model: HolidayQuoteViewModel
    let id: String
    private var strand: HLStrand { model.active.measurements.strands.first { $0.id == id } ?? HLStrand(fields: [:]) }
    var body: some View {
        Form {
            TextField("Strand name", text: Binding(get: { strand.label }, set: { label in update { $0.label = label } }))
            Section("Include runs") {
                ForEach(model.active.measurements.segments) { segment in
                    Toggle(segment.label, isOn: Binding(get: { strand.segmentIDs.contains(segment.id) }, set: { selected in
                        model.edit { option in
                            var groups = option.measurements.strands
                            for index in groups.indices {
                                groups[index].segmentIDs.removeAll { $0 == segment.id }
                                if selected && groups[index].id == id { groups[index].segmentIDs.append(segment.id) }
                            }
                            option.measurements.strands = groups
                        }
                    }))
                }
            }
        }.navigationTitle("Strand group")
    }
    private func update(_ change: (inout HLStrand) -> Void) {
        model.edit { option in var groups = option.measurements.strands; if let index = groups.firstIndex(where: { $0.id == id }) { change(&groups[index]); option.measurements.strands = groups } }
    }
}

struct HLPricingEditor: View {
    @ObservedObject var model: HolidayQuoteViewModel
    private var adjustment: HLAdjustment { model.active.selections.adjustments[model.active.selections.pricingMode] ?? HLAdjustment() }
    var body: some View {
        Form {
            Section("Option price adjustment") {
                Toggle("Override calculated subtotal", isOn: Binding(get: { adjustment.price != nil }, set: { enabled in change { $0.price = enabled ? (model.pricing?.optionDetails[model.active.selections.pricingMode]?.calculated ?? 0) : nil } }))
                if adjustment.price != nil { number("Subtotal", get: { adjustment.price ?? 0 }, set: { value in change { $0.price = max(0, value) } }) }
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
        }.navigationTitle("Price adjustments")
    }
    private func change(_ update: (inout HLAdjustment) -> Void) {
        model.edit(invalidatePreview: false) { option in var value = adjustment; update(&value); option.selections.adjustments[option.selections.pricingMode] = value }
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
        }.navigationTitle("Additional service")
    }
}
