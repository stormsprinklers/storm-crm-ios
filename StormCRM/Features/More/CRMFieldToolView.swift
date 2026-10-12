import SwiftUI
import WebKit
import UIKit

enum CRMFieldTool: String {
    case vehicles, holidayLighting, priceBook

    var title: String {
        switch self {
        case .vehicles: return "Vehicles"
        case .holidayLighting: return "Holiday Lighting"
        case .priceBook: return "Price Book"
        }
    }

    var path: String {
        switch self {
        case .vehicles: return "/vehicles"
        case .holidayLighting: return "/holiday-lighting/quote"
        case .priceBook: return "/price-book"
        }
    }
}

/// Uses the CRM's complete tools and records, with an isolated ephemeral web session.
struct CRMFieldToolView: View {
    let tool: CRMFieldTool
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var browser = CRMFieldToolBrowser()

    var body: some View {
        ZStack {
            CRMFieldWebView(browser: browser)
            if browser.isLoading {
                ProgressView("Loading \(tool.title)…")
                    .padding().background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if let error = browser.error {
                ContentUnavailableView {
                    Label("Could not load \(tool.title)", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await browser.open(tool: tool, api: env.apiClient) } }
                }
                .background(Color(.systemBackground))
            }
        }
        .navigationTitle(tool.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { browser.webView.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(!browser.canGoBack)
                Spacer()
                Button { browser.webView.reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
        .task {
            await browser.open(tool: tool, api: env.apiClient)
            // Renew cookies without reloading or discarding an in-progress quote/form.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(8 * 60)) } catch { return }
                do { try await browser.authenticate(api: env.apiClient) }
                catch { browser.error = (error as? APIError)?.message ?? error.localizedDescription }
            }
        }
        .onDisappear { browser.webView.stopLoading() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                do { try await browser.authenticate(api: env.apiClient) }
                catch { browser.error = (error as? APIError)?.message ?? error.localizedDescription }
            }
        }
    }
}

@MainActor
final class CRMFieldToolBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var isLoading = false
    @Published var error: String?
    @Published var canGoBack = false
    let webView: WKWebView
    private var cookieDomain: String?
    private var needsReload = true

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func open(tool: CRMFieldTool, api: APIClient) async {
        error = nil
        isLoading = true
        do {
            try await authenticate(api: api)
            guard !Task.isCancelled else { isLoading = false; return }
            guard let url = URL(string: AppConfig.apiBaseURL + tool.path) else { throw APIError.invalidURL }
            if needsReload || webView.url == nil {
                webView.load(URLRequest(url: webView.url ?? url))
            } else {
                // A retry after a renewal failure preserves the current quote/form.
                isLoading = false
            }
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
            isLoading = false
        }
    }

    func authenticate(api: APIClient) async throws {
        struct WebSession: Decodable {
            let sessionToken: String
            let cookieName: String
            let expiresIn: Int
        }
        guard let base = URL(string: AppConfig.apiBaseURL), let host = base.host else { throw APIError.invalidURL }
        let session: WebSession = try await api.post(path: APIPath.mobileWebSession)
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: host, .path: "/", .name: session.cookieName, .value: session.sessionToken,
            .expires: Date().addingTimeInterval(TimeInterval(session.expiresIn)),
            HTTPCookiePropertyKey("HttpOnly"): "TRUE",
            HTTPCookiePropertyKey("SameSite"): "Lax",
        ]
        if base.scheme == "https" { properties[.secure] = "TRUE" }
        guard let cookie = HTTPCookie(properties: properties) else { throw APIError.invalidURL }
        await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        properties[.name] = "crm-mobile-shell"
        properties[.value] = "1"
        guard let shellCookie = HTTPCookie(properties: properties) else { throw APIError.invalidURL }
        await webView.configuration.websiteDataStore.httpCookieStore.setCookie(shellCookie)
        cookieDomain = host
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        error = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        needsReload = false
        isLoading = false
        canGoBack = webView.canGoBack
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }

    private func failed(_ failure: Error) {
        if (failure as NSError).code == NSURLErrorCancelled { return }
        needsReload = true
        error = failure.localizedDescription
        isLoading = false
    }

    private var presenter: UIViewController? {
        var controller = webView.window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let presenter else { completionHandler(); return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let presenter else { completionHandler(false); return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        guard let presenter else { completionHandler(nil); return }
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        // Map/Street View frames stay in the tool. Only top-level external links leave the app.
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        guard let base = URL(string: AppConfig.apiBaseURL) else { decisionHandler(.cancel); return }
        if url.host == cookieDomain && url.scheme == base.scheme && url.port == base.port {
            if url.path == "/login" {
                needsReload = true
                error = "Your CRM session expired. Tap Retry to reconnect."
                isLoading = false
                decisionHandler(.cancel)
                return
            }
            if action.targetFrame == nil {
                webView.load(action.request)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
            return
        }
        decisionHandler(.cancel)
        if ["https", "http", "tel", "mailto", "stormcrm"].contains(url.scheme ?? "") {
            UIApplication.shared.open(url)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil // The navigation delegate routes new-window links to this view or the system browser.
    }
}

private struct CRMFieldWebView: UIViewRepresentable {
    let browser: CRMFieldToolBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
