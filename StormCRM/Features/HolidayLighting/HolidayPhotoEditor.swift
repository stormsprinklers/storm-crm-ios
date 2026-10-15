import SwiftUI
import PhotosUI
import UIKit

@MainActor
enum HLPhotoRenderer {
    static func jpeg(_ image: UIImage, strokes: [HLMarkupStroke] = []) throws -> Data {
        let scale = min(1, 1280 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let result = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
            for stroke in strokes {
                let path = UIBezierPath(); path.lineCapStyle = .round; path.lineJoinStyle = .round
                path.lineWidth = stroke.width * size.width
                for (index, point) in stroke.points.enumerated() {
                    let position = CGPoint(x: point.x * size.width, y: point.y * size.height)
                    if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                }
                UIColor(Color(hex: stroke.color) ?? .orange).withAlphaComponent(0.75).setStroke()
                if stroke.points.count == 1, let point = stroke.points.first {
                    let position = CGPoint(x: point.x * size.width, y: point.y * size.height)
                    path.addLine(to: CGPoint(x: position.x + 0.1, y: position.y))
                }
                path.stroke()
            }
        }
        guard let data = result.jpegData(compressionQuality: 0.78) else { throw APIError.badRequest("Could not prepare the property photo") }
        return data
    }
}

struct HLPhotoEditor: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var model: HolidayQuoteViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var camera = false
    @State private var stroke: HLMarkupStroke?
    @State private var brushWidth = 0.012
    @State private var heading = 0.0
    @State private var pitch = 0.0
    @State private var showClear = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = model.error { Text(error).foregroundStyle(.red) }
                if let notice = model.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                HStack {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Photo library", systemImage: "photo") }
                    Spacer()
                    Button { camera = true } label: { Label("Camera", systemImage: "camera") }
                }
                DisclosureGroup("Use Street View") {
                    LabeledContent("Heading", value: "\(Int(heading))°")
                    Slider(value: $heading, in: 0...360, step: 5)
                    LabeledContent("Pitch", value: "\(Int(pitch))°")
                    Slider(value: $pitch, in: -30...60, step: 5)
                    Button("Load Street View") { Task { await model.streetView(api: env.apiClient, heading: heading, pitch: pitch) } }
                }
                if let image = model.photo {
                    if model.photoUnsaved { Button("Save photo to quote") { Task { await model.uploadPhoto(image, api: env.apiClient) } }.buttonStyle(.borderedProminent) }
                    photoCanvas(image)
                    HStack {
                        Text("Brush").font(.caption)
                        Slider(value: $brushWidth, in: 0.003...0.06)
                        Button("Undo") { model.edit { if !$0.markup.isEmpty { $0.markup.removeLast() } } }.disabled(model.active.markup.isEmpty)
                        Button("Clear") { showClear = true }.disabled(model.active.markup.isEmpty)
                    }
                    Button { Task { await model.generatePreview(api: env.apiClient) } } label: { Label("Generate lighting preview", systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent).disabled(model.photoUnsaved || model.active.markup.isEmpty)
                } else { ContentUnavailableView("Choose a property photo", systemImage: "photo", description: Text("Take a picture, choose from your library, or load Street View.")) }
                if let preview = model.active.previewURL {
                    Text("\(model.active.label) preview").font(.headline)
                    AuthenticatedBlobImage(urlString: preview).frame(height: 300)
                }
                if model.generating { ProgressView("Generating and saving this option’s preview…").padding(.vertical) }
            }.padding()
        }
        .disabled(model.busy || model.generating)
        .overlay { if model.busy || model.generating { ProgressView(model.generating ? "Generating lighting preview…" : "Saving photo…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .navigationTitle("Photo and preview")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $camera) { CameraImagePicker { image in Task { await model.uploadPhoto(image, api: env.apiClient) } }.ignoresSafeArea() }
        .onChange(of: selectedPhoto) { _, item in
            Task {
                do {
                    guard let data = try await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw APIError.badRequest("Could not open this photo") }
                    await model.uploadPhoto(image, api: env.apiClient)
                } catch { model.error = (error as? APIError)?.message ?? error.localizedDescription }
            }
        }
        .confirmationDialog("Clear this option’s photo markup?", isPresented: $showClear, titleVisibility: .visible) {
            Button("Clear markup", role: .destructive) { model.edit { $0.markup = [] } }
            Button("Cancel", role: .cancel) {}
        }
    }
    private func photoCanvas(_ image: UIImage) -> some View {
        GeometryReader { geometry in
            ZStack {
                Image(uiImage: image).resizable().scaledToFit()
                Canvas { context, size in
                    for item in model.active.markup + (stroke.map { [$0] } ?? []) {
                        var path = Path()
                        for (index, point) in item.points.enumerated() {
                            let position = CGPoint(x: point.x * size.width, y: point.y * size.height)
                            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                        }
                        if item.points.count == 1, let point = item.points.first { path.addLine(to: CGPoint(x: point.x * size.width + 0.1, y: point.y * size.height)) }
                        context.stroke(path, with: .color((Color(hex: item.color) ?? .orange).opacity(0.75)), style: StrokeStyle(lineWidth: item.width * size.width, lineCap: .round, lineJoin: .round))
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard model.active.markup.count < 150 else { return }
                    let point = HLMarkupPoint(x: min(1, max(0, value.location.x / geometry.size.width)), y: min(1, max(0, value.location.y / geometry.size.height)))
                    if stroke == nil { stroke = HLMarkupStroke(points: [], width: brushWidth) }
                    if (stroke?.points.count ?? 0) < 1500 { stroke?.points.append(point) }
                }.onEnded { _ in
                    if let stroke { model.edit { $0.markup.append(stroke) } }
                    stroke = nil
                })
            }
        }
        .aspectRatio(image.size.width / max(1, image.size.height), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Property photo markup canvas")
    }
}
