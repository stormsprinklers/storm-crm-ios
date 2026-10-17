import SwiftUI
import PhotosUI
import UIKit

@MainActor
enum HLPhotoRenderer {
    static func jpeg(_ image: UIImage) throws -> Data {
        let scale = min(1, 1280 / max(image.size.width, image.size.height))
        let size = CGSize(width:max(1,image.size.width*scale),height:max(1,image.size.height*scale))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let result = UIGraphicsImageRenderer(size:size,format:format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin:.zero,size:size))
            image.draw(in:CGRect(origin:.zero,size:size))
        }
        guard let data = result.jpegData(compressionQuality:0.85) else { throw APIError.badRequest("Could not prepare the property photo") }
        return data
    }
}

struct HLPhotoEditor: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var model: HolidayQuoteViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var camera = false
    @State private var streetView = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                if let error = model.error { Text(error).foregroundStyle(.red) }
                HStack {
                    PhotosPicker(selection:$selectedPhoto,matching:.images) { Label("Photo library",systemImage:"photo") }
                    Spacer()
                    Button { camera = true } label: { Label("Camera",systemImage:"camera") }
                }
                Button("Street View") { streetView = true }
                if let image = model.photo {
                    Image(uiImage:image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:8))
                    Text("Preview instructions").font(.headline)
                    TextField("Colors, areas to light, and areas to leave unlit",text:Binding(get:{model.active.previewPrompt},set:{value in model.edit(invalidatePreview:false) { $0.previewPrompt = value }}),axis:.vertical)
                        .lineLimit(4...10).textFieldStyle(.roundedBorder)
                    Button { Task { await model.generatePreview(api:env.apiClient) } } label: { Label("Generate lighting preview",systemImage:"sparkles") }
                        .buttonStyle(.borderedProminent).disabled(model.generating || model.photoUnsaved)
                } else {
                    ContentUnavailableView("Choose a property photo",systemImage:"photo",description:Text("Take a picture, choose from your library, or load Street View."))
                }
                if let preview = model.active.previewURL {
                    Text("\(model.active.label) preview").font(.headline)
                    AuthenticatedBlobImage(urlString:preview).frame(height:300)
                }
            }.padding()
        }
        .background(HLKeyboardDismissal())
        .disabled(model.busy)
        .overlay { if model.busy { ProgressView("Saving photo…").padding().background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)) } }
        .navigationTitle("Photo and preview").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge:.top) { HLPreviewProgress(model:model) }
        .sheet(isPresented:$streetView) { HLStreetViewCapture(model:model) }
        .sheet(isPresented:$camera) { CameraImagePicker { image in Task { await model.uploadPhoto(image,api:env.apiClient) } }.ignoresSafeArea() }
        .onChange(of:selectedPhoto) { _,item in
            Task {
                do {
                    guard let data = try await item?.loadTransferable(type:Data.self),let image = UIImage(data:data) else { throw APIError.badRequest("Could not open this photo") }
                    await model.uploadPhoto(image,api:env.apiClient)
                } catch { model.error = (error as? APIError)?.message ?? error.localizedDescription }
            }
        }
    }
}
