import SwiftUI
import WebKit

struct HLStreetViewCapture: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: HolidayQuoteViewModel
    @State private var html: String?
    @State private var error: String?
    @State private var pano = ""
    @State private var heading = 0.0
    @State private var pitch = 0.0
    var body: some View {
        NavigationStack {
            VStack {
                if let html {
                    HLStreetPanorama(html: html) { value in
                        pano = value["pano"] as? String ?? ""
                        heading = value["heading"] as? Double ?? 0
                        pitch = value["pitch"] as? Double ?? 0
                    }
                    Button("Use this position") {
                        Task {
                            await model.streetView(api: env.apiClient, heading: heading, pitch: pitch, pano: pano)
                            if model.photoUnsaved, let photo = model.photo {
                                await model.uploadPhoto(photo, api: env.apiClient)
                                if !model.photoUnsaved { dismiss() }
                            }
                        }
                    }.buttonStyle(.borderedProminent).padding().disabled(pano.isEmpty || model.busy)
                } else if error == nil { ProgressView("Loading Street View…") }
                if let text = error ?? model.error { Text(text).foregroundStyle(.red).padding() }
            }.navigationTitle("Street View").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                guard await model.save(api: env.apiClient), let id = model.quoteID else { error = model.error; return }
                do {
                    let data = try await env.apiClient.getData(path: "/api/holiday-lighting/quotes/\(id)/photo", query: [URLQueryItem(name: "interactive", value: "true")])
                    html = String(data: data, encoding: .utf8)
                } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
            }
        }
    }
}
private struct HLStreetPanorama: UIViewRepresentable {
    let html: String
    let onPosition: ([String: Any]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPosition) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "position")
        let view = WKWebView(frame: .zero, configuration: config)
        view.loadHTMLString(html, baseURL: URL(string: AppConfig.apiBaseURL))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) { view.configuration.userContentController.removeScriptMessageHandler(forName: "position") }
    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onPosition: ([String: Any]) -> Void
        init(_ onPosition: @escaping ([String: Any]) -> Void) { self.onPosition = onPosition }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let value = message.body as? [String: Any] { onPosition(value) }
        }
    }
}
