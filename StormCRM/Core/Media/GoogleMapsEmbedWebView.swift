import SwiftUI
import WebKit

/// Loads a Google Maps Embed API URL inside an HTML iframe, as required by Google's terms.
///
/// By default the web view does not accept touches so it cannot steal vertical pans from a
/// parent `ScrollView` (visit header / customer property embeds). Pass `isInteractive: true`
/// only when the embed should handle gestures itself.
struct GoogleMapsEmbedWebView: UIViewRepresentable {
    let url: URL
    var isInteractive: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.isUserInteractionEnabled = isInteractive
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.isUserInteractionEnabled = isInteractive
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        webView.loadHTMLString(Self.iframeHTML(for: url, interactive: isInteractive), baseURL: nil)
    }

    private static func iframeHTML(for embedURL: URL, interactive: Bool) -> String {
        let escapedSrc = embedURL.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
        let pointerEvents = interactive ? "auto" : "none"

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body { width: 100%; height: 100%; overflow: hidden; background: transparent; }
        iframe { border: 0; width: 100%; height: 100%; display: block; pointer-events: \(pointerEvents); }
        </style>
        </head>
        <body>
        <iframe src="\(escapedSrc)" allowfullscreen loading="lazy" referrerpolicy="no-referrer-when-downgrade"></iframe>
        </body>
        </html>
        """
    }

    final class Coordinator {
        var loadedURL: URL?
    }
}
