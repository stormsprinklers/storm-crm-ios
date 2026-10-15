import SwiftUI
import MapKit
import PhotosUI
import UIKit

struct HolidayQuotesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var quotes: [HLQuote] = []
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        List {
            Section { NavigationLink { HolidayQuoteEditor() } label: { Label("New holiday quote", systemImage: "plus.circle.fill") } }
            if loading && quotes.isEmpty { ProgressView("Loading quotes…") }
            if let error { Text(error).foregroundStyle(.red); Button("Retry") { Task { await load() } } }
            if !loading && quotes.isEmpty && error == nil { Text("No holiday quotes yet.").foregroundStyle(.secondary) }
            ForEach(quotes) { quote in
                NavigationLink { HolidayQuoteEditor(quoteID: quote.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(quote.title.isEmpty ? "Untitled quote" : quote.title).font(.headline)
                        Text([quote.address, quote.city].compactMap { $0 }.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary)
                        Text([quote.status, quote.estimate?.estimateNumber].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Holiday Lighting")
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do { let response: HLQuoteListResponse = try await env.apiClient.get(path: "/api/holiday-lighting/quotes"); quotes = response.quotes }
        catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
    }
}

struct HolidayQuoteEditor: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: HolidayQuoteViewModel
    @State private var showCustomerPicker = false
    @State private var showProperties = false
    @State private var properties: [CustomerPropertyDTO] = []
    @State private var confirmLeave = false
    @State private var confirmReload = false
    @State private var estimateChoice = false
    @State private var estimateDestination: String?
    init(quoteID: String? = nil, visitID: String? = nil, customerID: String? = nil, propertyID: String? = nil) {
        _model = StateObject(wrappedValue: HolidayQuoteViewModel(quoteID: quoteID, visitID: visitID, customerID: customerID, propertyID: propertyID))
    }
    var body: some View {
        Form {
            if let error = model.error { Section { Text(error).foregroundStyle(.red); if model.quoteID != nil { Button("Reload saved quote…") { confirmReload = true } } } }
            if let notice = model.notice { Section { Text(notice).foregroundStyle(.secondary) } }
            propertySection
            optionTabs
            optionsSection
            designSection
            HLPricingFields(model: model)
            pricingSection
            Section {
                Button {
                    if model.estimateID != nil { estimateChoice = true }
                    else { Task { estimateDestination = await model.createEstimate(api: env.apiClient, revise: false) } }
                } label: { Label(model.estimateID == nil ? "Create estimate" : "Update / create estimate", systemImage: "doc.text") }
                .disabled(model.customerID == nil || !model.hasMeasurements)
                if let id = model.estimateID { NavigationLink("Open linked estimate") { EstimateDetailView(estimateId: id) } }
            }
            Section {
                TextField("Notes", text: model.selectionBinding(\.notes, invalidatePreview: false), axis: .vertical).lineLimit(3...8)
            } header: { stepHeader("Notes", id: "notes") }
        }
        .background(HLKeyboardDismissal())
        .disabled(model.busy || model.generating)
        .overlay { if model.busy { ProgressView("Saving / loading…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Back") { if model.dirty || model.photoUnsaved { confirmLeave = true } else { dismiss() } }.disabled(model.busy || model.generating) }
            ToolbarItem(placement: .topBarTrailing) { Button("Save") { Task { await model.save(api: env.apiClient) } }.disabled(model.busy || model.generating) }
        }
        .safeAreaInset(edge: .bottom) {
            HStack { Image(systemName: model.dirty ? "pencil.circle" : "checkmark.icloud"); Text(model.photoUnsaved ? "Photo not saved" : model.dirty ? "Unsaved changes" : "Saved").font(.caption); Spacer() }
                .padding(10).background(.regularMaterial)
        }
        .task { await model.load(api: env.apiClient); if model.center == nil && !model.address.isEmpty { await model.locate(api: env.apiClient) } }
        .sheet(isPresented: $showCustomerPicker) { NavigationStack { HLCustomerPicker { model.chooseCustomer($0); showCustomerPicker = false; Task { await model.locate(api: env.apiClient) } } } }
        .confirmationDialog("Select property", isPresented: $showProperties, titleVisibility: .visible) {
            ForEach(properties) { property in Button(property.name + " — " + property.formattedAddress) { model.applyProperty(property); Task { await model.locate(api: env.apiClient) } } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Save your quote before leaving?", isPresented: $confirmLeave) {
            Button("Save and leave") { Task {
                if model.photoUnsaved, let photo = model.photo { await model.uploadPhoto(photo, api: env.apiClient) }
                if !model.photoUnsaved, await model.save(api: env.apiClient) { dismiss() }
            } }
            Button("Discard unsaved changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .confirmationDialog("Reload the CRM version? This discards unsaved changes on this screen.", isPresented: $confirmReload, titleVisibility: .visible) {
            Button("Reload", role: .destructive) { Task { await model.reload(api: env.apiClient) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("An estimate is already linked", isPresented: $estimateChoice, titleVisibility: .visible) {
            Button("Revise linked estimate") { Task { estimateDestination = await model.createEstimate(api: env.apiClient, revise: true) } }
            Button("Create a new estimate") { Task { estimateDestination = await model.createEstimate(api: env.apiClient, revise: false) } }
            Button("Cancel", role: .cancel) {}
        }
        .navigationDestination(isPresented: Binding(get: { estimateDestination != nil }, set: { if !$0 { estimateDestination = nil } })) {
            if let id = estimateDestination { EstimateDetailView(estimateId: id) }
        }
    }
    private var propertySection: some View {
        Section {
            Button(model.customerName.isEmpty ? "Choose customer" : model.customerName) { showCustomerPicker = true }.disabled(model.linkedVisit)
            if model.customerID != nil {
                Button(model.propertyID == nil ? "Choose customer property" : model.address.isEmpty ? "Selected property" : model.address) {
                    Task {
                        do { properties = try await env.apiClient.get(path: APIPath.customerProperties(model.customerID!)); showProperties = true }
                        catch { model.error = (error as? APIError)?.message ?? error.localizedDescription }
                    }
                }.disabled(model.linkedVisit)
            }
            TextField("Street address", text: addressBinding(\.address)).textContentType(.streetAddressLine1)
            TextField("City", text: addressBinding(\.city)).textContentType(.addressCity)
            HStack { TextField("State", text: addressBinding(\.state)); TextField("ZIP", text: addressBinding(\.zip)).keyboardType(.numbersAndPunctuation) }
        } header: { stepHeader("Customer and property", id: "property") }
    }
    private func addressBinding(_ path: ReferenceWritableKeyPath<HolidayQuoteViewModel, String>) -> Binding<String> {
        Binding(get: { model[keyPath: path] }, set: { model[keyPath: path] = $0; model.center = nil; model.dirty = true })
    }
    private func stepHeader(_ title: String, id: String) -> some View {
        Button {
            model.edit(invalidatePreview: false) { option in
                if option.selections.completedSteps.contains(id) { option.selections.completedSteps.removeAll { $0 == id } }
                else { option.selections.completedSteps.append(id) }
            }
        } label: {
            Label(title, systemImage: model.active.selections.completedSteps.contains(id) ? "checkmark.square.fill" : "square")
        }.buttonStyle(.plain).textCase(nil).accessibilityLabel("\(title), \(model.active.selections.completedSteps.contains(id) ? "complete" : "incomplete")")
    }
    private var optionTabs: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(model.options) { option in
                        Button { model.selectOption(option.id) } label: {
                            Text(option.label).fontWeight(model.activeID == option.id ? .bold : .regular)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(model.activeID == option.id ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(model.activeID == option.id ? .isSelected : [])
                    }
                }
            }
        }
    }
    private var optionsSection: some View {
        Section {
            TextField("Option name", text: model.optionBinding(\.label))
            HStack {
                Button("Add option") { model.addOption(copy: false) }.disabled(model.options.count >= 5)
                Spacer()
                Button("Copy option") { model.addOption(copy: true) }.disabled(model.options.count >= 5)
            }
            if model.options.count > 1 { Button("Remove this option", role: .destructive) { model.deleteOption() } }
            Picker("Default bulbs", selection: model.selectionBinding(\.style)) {
                ForEach(model.catalog?.lightStyles ?? []) { style in Text(style.label).tag(style.key) }
            }
            HLColorField(value: model.selectionBinding(\.color))
            Picker("Pricing", selection: model.selectionBinding(\.pricingMode, invalidatePreview: false)) {
                if model.active.selections.style == "permanent" { Text("Permanent").tag("permanent") }
                else { Text("Buy lights + labor").tag("buy"); Text("Lease").tag("lease"); Text("Labor only").tag("labor") }
            }
            if model.active.selections.pricingMode == "lease" {
                Picker("Lease term", selection: model.selectionBinding(\.leaseYears, invalidatePreview: false)) { Text("1 year").tag(1); Text("3 years").tag(3); Text("5 years").tag(5) }
            }
        } header: { stepHeader("Options", id: "options") }
    }
    @ViewBuilder private var designSection: some View {
        Section {
            if let center = model.center {
                Map(initialPosition: .region(MKCoordinateRegion(center: center.coordinate, latitudinalMeters: 110, longitudinalMeters: 110))) {
                    ForEach(model.active.measurements.segments) { segment in
                        MapPolyline(coordinates: segment.path.map(\.coordinate)).stroke(.orange, lineWidth: 4)
                    }
                    ForEach(model.active.measurements.placements) { placement in
                        Marker(placement.label, systemImage: placement.kind == "tree" ? "tree.fill" : "leaf.fill", coordinate: placement.point.coordinate)
                    }
                }.mapStyle(.imagery(elevation: .flat)).frame(height: 240).id("\(center.lat),\(center.lng)")
            }
            Button(model.center == nil ? "Find property on aerial map" : "Recenter property") { Task { await model.locate(api: env.apiClient) } }
                .disabled(model.address.trimmingCharacters(in: .whitespaces).isEmpty)
            NavigationLink { HolidayAerialEditor(model: model) } label: { Label("Measure and draw aerial plan", systemImage: "map") }
            NavigationLink { HLMeasurementList(model: model) } label: { Label("Manual Measurements", systemImage: "ruler") }
        } header: { stepHeader("Design", id: "design") }
        Section {
            NavigationLink { HLPhotoEditor(model: model) } label: { Label("Property photo and lighting preview", systemImage: "paintbrush.pointed") }
            if let preview = model.active.previewURL { AuthenticatedBlobImage(urlString: preview).frame(height: 220) }
        } header: { stepHeader("Photo and preview", id: "photo") }
    }
    private var pricingSection: some View {
        Section {
            Button("Save and calculate price") { Task { await model.save(api: env.apiClient) } }
            if !model.dirty, let pricing = model.pricing, let detail = pricing.optionDetails[model.active.selections.pricingMode] {
                LabeledContent("Option total", value: detail.total.formatted(.currency(code: "USD")))
                LabeledContent("Measured / billed length", value: "\(pricing.billedLengthFt.formatted(.number.precision(.fractionLength(1)))) ft")
                if detail.discountTotal > 0 { LabeledContent("Discount", value: detail.discountTotal.formatted(.currency(code: "USD"))) }
                LabeledContent("Reinstall", value: pricing.reinstallTotal.formatted(.currency(code: "USD")))
            }
            if !model.dirty, let lines = model.pricing?.optionDetails[model.active.selections.pricingMode]?.displayLines {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    LabeledContent(line.name, value: line.total.formatted(.currency(code: "USD")))
                }
            }
        } header: { stepHeader("Price and line items", id: "price") }
    }
}

private struct HLCustomerPicker: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = CustomersListViewModel()
    @State private var search = ""
    let onSelect: (CustomerDTO) -> Void
    var body: some View {
        List {
            if let error = model.error { Text(error).foregroundStyle(.red) }
            if model.isLoading { ProgressView() }
            ForEach(model.customers) { customer in Button { onSelect(customer) } label: { VStack(alignment: .leading) { Text(customer.name); Text(customer.formattedAddress).font(.caption).foregroundStyle(.secondary) } } }
        }
        .navigationTitle("Choose customer")
        .searchable(text: $search)
        .task(id: search) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            await model.load(api: env.apiClient, search: search)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                if let role = env.auth.user?.role, UserRoles.canEditCustomers(role) {
                    NavigationLink("New") {
                        NewCustomerView { id in
                            Task {
                                do { let customer: CustomerDTO = try await env.apiClient.get(path: APIPath.customer(id)); onSelect(customer) }
                                catch { model.error = (error as? APIError)?.message ?? error.localizedDescription }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct HLColorField: View {
    @Binding var value: String
    var body: some View {
        HStack {
            TextField("Bulb color / repeating pattern", text: $value)
            Menu { ForEach(holidayBulbColors, id: \.self) { color in Button(color) { value = color } } } label: { Image(systemName: "paintpalette") }.accessibilityLabel("Choose bulb color")
        }
    }
}

// Observe taps without swallowing buttons, map gestures, or text-field focus.
struct HLKeyboardDismissal: UIViewRepresentable {
    final class TapView: UIView, UIGestureRecognizerDelegate {
        weak var attachedWindow: UIWindow?
        lazy var tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachedWindow?.removeGestureRecognizer(tap)
            attachedWindow = window
            tap.cancelsTouchesInView = false; tap.delegate = self
            window?.addGestureRecognizer(tap)
        }
        @objc private func dismissKeyboard() { window?.endEditing(true) }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
    func makeUIView(context: Context) -> TapView { TapView() }
    func updateUIView(_ uiView: TapView, context: Context) {}
    static func dismantleUIView(_ uiView: TapView, coordinator: ()) { uiView.attachedWindow?.removeGestureRecognizer(uiView.tap) }
}
