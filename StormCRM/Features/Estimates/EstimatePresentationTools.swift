import SwiftUI
import PDFKit

struct EstimatePDFView: View {
    @EnvironmentObject private var env: AppEnvironment
    let estimateId: String
    let optionCount: Int
    @State private var option = 0
    @State private var data: Data?
    @State private var error: String?
    var body: some View {
        VStack {
            if optionCount > 1 {
                Picker("Option PDF", selection: $option) { ForEach(0..<optionCount, id: \.self) { Text("Option \($0 + 1)").tag($0) } }.pickerStyle(.menu)
            }
            if let data { PDFDocumentView(data: data) }
            else if let error { Text(error).foregroundStyle(.red) }
            else { ProgressView("Loading PDF…") }
        }.task(id: option) {
            data = nil; error = nil
            do { data = try await env.apiClient.getData(path: "/api/estimates/\(estimateId)/pdf",query:[URLQueryItem(name:"option",value:String(option))]) }
            catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
        }.navigationTitle("Estimate PDF")
    }
}
private struct PDFDocumentView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.document = PDFDocument(data: data); return view }
    func updateUIView(_ view: PDFView, context: Context) { if view.document?.dataRepresentation() != data { view.document = PDFDocument(data:data) } }
}

struct EstimatePresentationEditor: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let estimateId: String
    let options: [EstimateOptionDTO]
    var onSaved: () async -> Void
    @State private var labels: [String:String] = [:]
    @State private var descriptions: [String:String] = [:]
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        Form {
            ForEach(options) { option in
                Section(option.label) {
                    TextField("Option name",text:Binding(get:{labels[option.id] ?? option.label},set:{labels[option.id]=$0}))
                    TextField("Description",text:Binding(get:{descriptions[option.id] ?? option.description ?? ""},set:{descriptions[option.id]=$0}),axis:.vertical).lineLimit(4...12)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Edit presentation")
        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Save") { Task { await save() } }.disabled(saving) } }
    }
    private func save() async {
        saving=true; error=nil; defer{saving=false}
        do {
            struct Body: Encodable {let optionId:String; let label:String;let description:String}
            for option in options {
                let _: EmptyResponse = try await env.apiClient.patch(path:APIPath.estimateOptions(estimateId),body:Body(optionId:option.id,label:labels[option.id] ?? option.label,description:descriptions[option.id] ?? option.description ?? ""))
            }
            await onSaved(); dismiss()
        } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
    }
}
