import SwiftUI

struct IrrigationMapEditorView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: IrrigationMapEditorViewModel
    @State private var draftPoints: ImagePolygon = []
    @State private var renamingZoneIndex: Int?
    @State private var renameText = ""
    @State private var showCrop = false

    init(customerId: String, propertyId: String, propertyName: String) {
        _viewModel = StateObject(
            wrappedValue: IrrigationMapEditorViewModel(
                customerId: customerId,
                propertyId: propertyId,
                propertyName: propertyName
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                ProgressView("Loading map…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    headerBar
                        .padding(.horizontal)
                        .padding(.top, 8)

                    mapSection
                        .padding(.horizontal)

                    Text("Tap to place points · Pinch to zoom · Double-tap to reset zoom")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        zoneTabs
                        drawControls
                        markerControls
                        systemFields
                        activeZoneAttributes
                        programSection
                        RachioPropertySection(
                            customerId: viewModel.customerId,
                            propertyId: viewModel.propertyId
                        )
                    }
                    .padding()
                }
            }
        }
        .background(StormTheme.page.ignoresSafeArea())
        .navigationTitle(viewModel.propertyName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Rename zone", isPresented: Binding(
            get: { renamingZoneIndex != nil },
            set: { if !$0 { renamingZoneIndex = nil } }
        )) {
            TextField("Zone name", text: $renameText)
            Button("Save") {
                if let index = renamingZoneIndex {
                    viewModel.renameZone(at: index, name: renameText)
                }
                renamingZoneIndex = nil
            }
            Button("Cancel", role: .cancel) { renamingZoneIndex = nil }
        }
        .task { await viewModel.load(api: env.apiClient) }
        .onChange(of: viewModel.markerPlacement) { _, _ in draftPoints = [] }
        .sheet(isPresented: $showCrop) {
            if let url = viewModel.mapImageUrl {
                IrrigationAerialCropView(imageUrl: url, isBusy: viewModel.isCapturingAerial) { crop in
                    Task {
                        await viewModel.cropAerial(api: env.apiClient, crop: crop)
                        if viewModel.error == nil {
                            showCrop = false
                            draftPoints = []
                        }
                    }
                }
                .environmentObject(env)
            }
        }
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StormSectionHeader(title: "Irrigation map editor", systemImage: "map")
                Spacer()
                if viewModel.mapStatus == "PUBLISHED" {
                    StormBadge(text: "Published", style: .success)
                } else {
                    StormBadge(text: "Draft", style: .neutral)
                }
            }

            if let error = viewModel.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if let message = viewModel.successMessage {
                Text(message).font(.caption).foregroundStyle(StormTheme.success)
            }

            // Wrap so buttons never force horizontal page scroll on small phones.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                Button(viewModel.isCapturingAerial ? "Capturing…" : "Capture aerial") {
                    Task { await viewModel.captureAerial(api: env.apiClient) }
                }
                .buttonStyle(StormSecondaryButtonStyle())
                .disabled(viewModel.isCapturingAerial)

                if viewModel.mapImageUrl != nil {
                    Button {
                        showCrop = true
                    } label: {
                        Label("Zoom in", systemImage: "plus.magnifyingglass")
                    }
                    .buttonStyle(StormSecondaryButtonStyle())
                    .disabled(viewModel.isCapturingAerial)
                }

                Button(viewModel.isSaving ? "Saving…" : "Save draft") {
                    Task { await viewModel.save(api: env.apiClient, publish: false) }
                }
                .buttonStyle(StormSecondaryButtonStyle())
                .disabled(viewModel.isSaving)

                Button("Publish") {
                    Task { await viewModel.save(api: env.apiClient, publish: true) }
                }
                .buttonStyle(StormPrimaryButtonStyle())
                .disabled(viewModel.isSaving)
            }
        }
    }

    private var mapSection: some View {
        GeometryReader { geo in
            IrrigationMapEditorCanvas(
                imageUrl: viewModel.mapImageUrl,
                zones: viewModel.zones,
                markers: viewModel.markers,
                activeZoneIndex: viewModel.activeZoneIndex,
                draftPoints: draftPoints,
                readOnly: false,
                height: IrrigationMapSizing.preferredHeight(forWidth: geo.size.width),
                onTap: handleMapTap
            )
        }
        .frame(height: IrrigationMapSizing.preferredHeight(forWidth: UIScreen.main.bounds.width - 32))
    }

    private var zoneTabs: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Zones").font(.subheadline.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(viewModel.zones.enumerated()), id: \.element.id) { index, zone in
                        zoneTab(index: index, zone: zone)
                    }
                    Button {
                        viewModel.addZone()
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(StormSecondaryButtonStyle())
                }
            }
        }
    }

    private func zoneTab(index: Int, zone: EditableIrrigationZone) -> some View {
        let isActive = index == viewModel.activeZoneIndex
        let hasPolygon = zone.polygon != nil
        return HStack(spacing: 4) {
            Button {
                viewModel.activeZoneIndex = index
                draftPoints = []
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: PolygonGeometry.zoneColor(index: index)) ?? StormTheme.sky)
                        .frame(width: 10, height: 10)
                    Text(zone.name)
                        .font(.caption)
                        .lineLimit(1)
                    if hasPolygon {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(StormTheme.success)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isActive ? StormTheme.ice : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? StormTheme.sky : StormTheme.ice, lineWidth: 1)
                )
            }

            Button {
                renameText = zone.name
                renamingZoneIndex = index
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
            }

            if viewModel.zones.count > 1 {
                Button(role: .destructive) {
                    viewModel.removeZone(at: index)
                    draftPoints = []
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
            }
        }
    }

    private var drawControls: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Draw zone \(viewModel.zones[safe: viewModel.activeZoneIndex]?.name ?? "")")
                    .font(.subheadline.bold())
                Text("Tap the map to place corners. Need at least 3 points.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Complete polygon") { completePolygon() }
                        .buttonStyle(StormPrimaryButtonStyle())
                        .disabled(draftPoints.count < 3)
                }
                HStack {
                    Button("Undo point") {
                        if !draftPoints.isEmpty { draftPoints.removeLast() }
                    }
                    .buttonStyle(StormSecondaryButtonStyle())
                    .disabled(draftPoints.isEmpty)

                    Button("Clear zone") {
                        viewModel.setPolygon(at: viewModel.activeZoneIndex, polygon: nil)
                        draftPoints = []
                    }
                    .buttonStyle(StormSecondaryButtonStyle())
                }

                if !draftPoints.isEmpty {
                    Text("\(draftPoints.count) point(s) placed")
                        .font(.caption)
                        .foregroundStyle(StormTheme.coral)
                }
            }
        }
    }

    private var markerControls: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Map markers").font(.subheadline.bold())
                Text(viewModel.markerPlacement == nil
                     ? "Select a marker type, then tap the map to place it."
                     : "Tap the map to place \(IrrigationConstants.markerStyle(for: viewModel.markerPlacement!).label).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(IrrigationConstants.markerKinds, id: \.type) { kind in
                            Button {
                                viewModel.markerPlacement = viewModel.markerPlacement == kind.type ? nil : kind.type
                                draftPoints = []
                            } label: {
                                Text(kind.label)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(viewModel.markerPlacement == kind.type ? StormTheme.sky.opacity(0.2) : StormTheme.ice.opacity(0.3))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                if !viewModel.markers.isEmpty {
                    ForEach(viewModel.markers) { marker in
                        HStack {
                            let style = IrrigationConstants.markerStyle(for: marker.type)
                            Circle()
                                .fill(Color(hex: style.color) ?? StormTheme.navy)
                                .frame(width: 8, height: 8)
                            Text("\(style.label): \(marker.label)")
                                .font(.caption)
                            Spacer()
                            Button(role: .destructive) {
                                viewModel.removeMarker(id: marker.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var systemFields: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("System info").font(.subheadline.bold())

                Picker("Water source", selection: $viewModel.waterSource) {
                    Text("Not set").tag("")
                    ForEach(IrrigationConstants.waterSources) { option in
                        Text(option.label).tag(option.value)
                    }
                }

                TextField("Shutoff valve location", text: $viewModel.shutoffLocation)
                    .textFieldStyle(.roundedBorder)
                TextField("Controller location", text: $viewModel.controllerLocation)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    private var activeZoneAttributes: some View {
        if viewModel.activeZoneIndex >= 0, viewModel.activeZoneIndex < viewModel.zones.count {
            IrrigationZoneAttributesForm(
                zone: Binding(
                    get: { viewModel.zones[viewModel.activeZoneIndex] },
                    set: { viewModel.zones[viewModel.activeZoneIndex] = $0 }
                )
            )
        }
    }

    private var programSection: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 12) {
                StormSectionHeader(title: "Controller program", systemImage: "clock")

                IrrigationProgramSettingsForm(
                    grassSeason: $viewModel.grassSeason,
                    droughtRestrictions: $viewModel.droughtRestrictions,
                    cycleSoakEnabled: $viewModel.cycleSoakEnabled,
                    etoOverride: $viewModel.etoOverride,
                    onSave: { Task { await viewModel.saveProgramSettings(api: env.apiClient) } },
                    onRefreshWeather: { Task { await viewModel.refreshProgramGuide(api: env.apiClient) } },
                    isSaving: viewModel.isSaving
                )

                if let guide = viewModel.programGuide {
                    Divider()
                    IrrigationProgramGuideView(guide: guide)
                }
            }
        }
    }

    private func handleMapTap(_ point: ImagePoint) {
        if let placement = viewModel.markerPlacement {
            viewModel.placeMarker(type: placement, at: point)
            return
        }
        draftPoints.append(point)
    }

    private func completePolygon() {
        guard draftPoints.count >= 3 else { return }
        viewModel.setPolygon(at: viewModel.activeZoneIndex, polygon: draftPoints)
        draftPoints = []
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
