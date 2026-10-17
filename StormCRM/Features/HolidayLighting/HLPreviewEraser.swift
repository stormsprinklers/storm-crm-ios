import SwiftUI
import UIKit

struct HLPreviewEraser: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: HolidayQuoteViewModel
    let option: HLDesign
    @State private var house: UIImage?
    @State private var lights: UIImage?
    @State private var strokes: [HLMarkupStroke] = []
    @State private var current: HLMarkupStroke?
    @State private var width = 0.025
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let house, let lights {
                        GeometryReader { geometry in
                            ZStack {
                                Image(uiImage: house).resizable().scaledToFit()
                                Image(uiImage: erased(lights, strokes: strokes + (current.map { [$0] } ?? []))).resizable().scaledToFit()
                            }.contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if current == nil { current = HLMarkupStroke(width: width) }
                                        current?.points.append(HLMarkupPoint(x: min(1,max(0,value.location.x/geometry.size.width)), y: min(1,max(0,value.location.y/geometry.size.height))))
                                    }
                                    .onEnded { _ in if let current { strokes.append(current) }; current = nil })
                        }.aspectRatio(house.size.width/house.size.height, contentMode: .fit)
                        HStack {
                            Image(systemName: "eraser")
                            Slider(value: $width, in: 0.005...0.1)
                            Button("Undo") { if !strokes.isEmpty { strokes.removeLast() } }.disabled(strokes.isEmpty)
                            Button("Reset") { strokes = [] }.disabled(strokes.isEmpty)
                        }
                    } else if error == nil { ProgressView("Loading preview…") }
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding()
            }.disabled(saving)
                .navigationTitle("Erase lights").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await save() } } label: { if saving { ProgressView() } else { Text("Save") } }
                            .disabled(saving || lights == nil || strokes.isEmpty)
                    }
                }
                .task {
                    do {
                        guard let backgroundURL = option.previewBackgroundURL, let lightsURL = option.previewLightsURL else { throw APIError.badRequest("Regenerate this preview to enable light erasing.") }
                        async let background = load(backgroundURL)
                        async let overlay = load(lightsURL)
                        house = try await background; lights = try await overlay
                    } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
                }
        }
    }
    private func load(_ stored: String) async throws -> UIImage {
        guard let url = BlobImageURL.resolved(stored) else { throw APIError.badRequest("Invalid preview image") }
        let data: Data
        if url.host == URL(string: AppConfig.apiBaseURL)?.host {
            data = try await env.apiClient.getData(path: url.path, query: URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems ?? [])
        } else { data = try await URLSession.shared.data(from: url).0 }
        guard let image = UIImage(data:data) else { throw APIError.badRequest("Could not load preview image") }
        return image
    }
    private func erased(_ image: UIImage, strokes: [HLMarkupStroke]) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size:image.size,format:format).image { context in
            image.draw(in:CGRect(origin:.zero,size:image.size))
            context.cgContext.setBlendMode(.clear)
            for stroke in strokes {
                let path = UIBezierPath(); path.lineWidth = stroke.width*image.size.width; path.lineCapStyle = .round; path.lineJoinStyle = .round
                for (index,point) in stroke.points.enumerated() {
                    let location = CGPoint(x:point.x*image.size.width,y:point.y*image.size.height)
                    if index == 0 { path.move(to:location) } else { path.addLine(to:location) }
                }
                if stroke.points.count == 1, let p = stroke.points.first { path.addLine(to:CGPoint(x:p.x*image.size.width+0.1,y:p.y*image.size.height)) }
                path.stroke()
            }
        }
    }
    private func save() async {
        guard let lights, let quoteID = model.quoteID else { return }
        saving = true; error = nil; defer { saving = false }
        do {
            guard await model.save(api:env.apiClient) else { throw APIError.badRequest(model.error ?? "Could not save the quote") }
            guard let png = erased(lights,strokes:strokes).pngData(), png.count < 4*1024*1024 else { throw APIError.badRequest("The lights layer is too large to save") }
            let _: EmptyResponse = try await env.apiClient.uploadImages(path:"/api/holiday-lighting/quotes/\(quoteID)/preview-edit", fields:["optionId":option.id,"expectedPreviewUrl":option.previewURL ?? ""],images:[("lights",png)])
            let response: HLQuoteResponse = try await env.apiClient.get(path:"/api/holiday-lighting/quotes/\(quoteID)")
            model.apply(response); dismiss()
        } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
    }
}
