import SwiftUI
import MapKit
import PhotosUI

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
            optionsSection
            designSection
            pricingSection
            Section {
                Button {
                    if model.estimateID != nil { estimateChoice = true }
                    else { Task { estimateDestination = await model.createEstimate(api: env.apiClient, revise: false) } }
                } label: { Label(model.estimateID == nil ? "Create estimate" : "Update / create estimate", systemImage: "doc.text") }
                .disabled(model.customerID == nil || !model.hasMeasurements)
                if let id = model.estimateID { NavigationLink("Open linked estimate") { EstimateDetailView(estimateId: id) } }
            } footer: { Text("Estimates use the same company price book, options and approval flow as the main CRM. Creating an estimate does not send it to the customer.") }
        }
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
            HStack { Image(systemName: model.dirty ? "pencil.circle" : "checkmark.icloud"); Text(model.photoUnsaved ? "Property photo not saved" : model.dirty ? "Unsaved changes — Save to sync and calculate" : "Synced with CRM").font(.caption); Spacer() }
                .padding(10).background(.regularMaterial)
        }
        .task { await model.load(api: env.apiClient) }
        .sheet(isPresented: $showCustomerPicker) { NavigationStack { HLCustomerPicker { model.chooseCustomer($0); showCustomerPicker = false } } }
        .confirmationDialog("Select property", isPresented: $showProperties, titleVisibility: .visible) {
            ForEach(properties) { property in Button(property.name + " — " + property.formattedAddress) { model.applyProperty(property) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Save your quote before leaving?", isPresented: $confirmLeave, titleVisibility: .visible) {
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
        Section("Customer and property") {
            Button(model.customerName.isEmpty ? "Choose customer" : model.customerName) { showCustomerPicker = true }.disabled(model.linkedVisit)
            if model.customerID != nil {
                Button("Choose customer property") {
                    Task {
                        do { properties = try await env.apiClient.get(path: APIPath.customerProperties(model.customerID!)); showProperties = true }
                        catch { model.error = (error as? APIError)?.message ?? error.localizedDescription }
                    }
                }.disabled(model.linkedVisit)
            }
            TextField("Street address", text: addressBinding(\.address)).textContentType(.streetAddressLine1)
            TextField("City", text: addressBinding(\.city)).textContentType(.addressCity)
            HStack { TextField("State", text: addressBinding(\.state)); TextField("ZIP", text: addressBinding(\.zip)).keyboardType(.numbersAndPunctuation) }
            Button("Find property on aerial map") { Task { await model.locate(api: env.apiClient) } }.disabled(model.address.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
    private func addressBinding(_ path: ReferenceWritableKeyPath<HolidayQuoteViewModel, String>) -> Binding<String> {
        Binding(get: { model[keyPath: path] }, set: { model[keyPath: path] = $0; model.dirty = true })
    }
    private var optionsSection: some View {
        Section("Quote options") {
            Picker("Editing", selection: Binding(get: { model.activeID }, set: { model.selectOption($0) })) {
                ForEach(model.options) { option in Text(option.label).tag(option.id) }
            }
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
            Text("Default bulbs and colors apply to new runs. Edit existing runs in Measurements.").font(.caption).foregroundStyle(.secondary)
            Picker("Pricing", selection: model.selectionBinding(\.pricingMode, invalidatePreview: false)) {
                if model.active.selections.style == "permanent" { Text("Permanent").tag("permanent") }
                else { Text("Buy lights + labor").tag("buy"); Text("Lease").tag("lease"); Text("Labor only").tag("labor") }
            }
            if model.active.selections.pricingMode == "lease" {
                Picker("Lease term", selection: model.selectionBinding(\.leaseYears, invalidatePreview: false)) { Text("1 year").tag(1); Text("3 years").tag(3); Text("5 years").tag(5) }
            }
            TextField("Notes", text: model.selectionBinding(\.notes, invalidatePreview: false), axis: .vertical).lineLimit(3...8)
        }
    }
    private var designSection: some View {
        Section("Design") {
            NavigationLink { HolidayAerialEditor(model: model) } label: { Label("Measure and draw aerial plan", systemImage: "map") }
            Text("\(model.active.measurements.segments.count) rooflines · \(model.active.measurements.placements.count) trees / bushes · \(model.active.measurements.strands.count) strands").font(.caption).foregroundStyle(.secondary)
            NavigationLink { HLMeasurementList(model: model) } label: { Label("Measurements, bulbs and strands", systemImage: "ruler") }
            NavigationLink { HLPhotoEditor(model: model) } label: { Label("Property photo and lighting preview", systemImage: "paintbrush.pointed") }
            if let preview = model.active.previewURL { AuthenticatedBlobImage(urlString: preview).frame(height: 220) }
        }
    }
    private var pricingSection: some View {
        Section {
            Button("Save and calculate price") { Task { await model.save(api: env.apiClient) } }
            if !model.dirty, let pricing = model.pricing, let detail = pricing.optionDetails[model.active.selections.pricingMode] {
                LabeledContent("Option total", value: detail.total.formatted(.currency(code: "USD")))
                LabeledContent("Measured / billed length", value: "\(pricing.billedLengthFt.formatted(.number.precision(.fractionLength(1)))) ft")
                if detail.discountTotal > 0 { LabeledContent("Discount", value: detail.discountTotal.formatted(.currency(code: "USD"))) }
                LabeledContent("Reinstall", value: pricing.reinstallTotal.formatted(.currency(code: "USD")))
                if pricing.year1MinimumApplied || pricing.permanentMinimumApplied { Text("Company minimum pricing applied.").font(.caption).foregroundStyle(.secondary) }
            }
            NavigationLink("Price adjustments and additional services") { HLPricingEditor(model: model) }
        } header: { Text("Price") } footer: { Text("Calculated by the CRM using current company prices. Save changes to refresh totals.") }
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
