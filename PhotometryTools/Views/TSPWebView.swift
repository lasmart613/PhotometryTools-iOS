import SwiftUI
import WebKit

/// Loads bundled HTML from `Resources/assets` into a WKWebView.
struct TSPWebView: UIViewRepresentable {
    let resourceName: String
    let subdirectory: String?

    func makeUIView(context: Context) -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        loadBundledPage(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private func loadBundledPage(in webView: WKWebView) {
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "html",
            subdirectory: subdirectory
        ) else {
            webView.loadHTMLString(Self.missingAssetHTML, baseURL: nil)
            return
        }

        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private static let missingAssetHTML = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>TSP shell</title>
    </head>
    <body style="font-family:-apple-system,sans-serif;padding:24px;background:#0f1419;color:#e8eef4;">
      <h1>Assets not found</h1>
      <p>Expected <code>Resources/assets/index.html</code> in the app bundle.</p>
    </body>
    </html>
    """
}
