import SwiftUI
import WebKit

/// Loads a Google Maps Embed API URL inside an HTML iframe, as required by Google's terms.
struct GoogleMapsEmbedWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        webView.loadHTMLString(Self.iframeHTML(for: url), baseURL: nil)
    }

    private static func iframeHTML(for embedURL: URL) -> String {
        let escapedSrc = embedURL.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body { width: 100%; height: 100%; overflow: hidden; background: transparent; }
        iframe { border: 0; width: 100%; height: 100%; display: block; }
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
