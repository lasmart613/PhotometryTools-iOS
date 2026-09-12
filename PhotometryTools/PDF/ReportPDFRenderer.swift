import Foundation
import WebKit

/// Renders the HTML `Android.printReport(html, jobName)` payload to a PDF.
/// Mirrors Android `MainActivity.printReport` → `PdfDocument` without a print dialog.
@MainActor
final class ReportPDFRenderer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Data, Error>?

    func render(html: String) async throws -> Data {
        if continuation != nil {
            continuation?.resume(throwing: ManualURLClient.Failure.invalidResponse)
            continuation = nil
        }

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: 1123), configuration: configuration)
        view.isOpaque = true
        view.backgroundColor = .white
        view.navigationDelegate = self
        webView = view

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            view.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Let late layout (images / tables) settle, same 300ms delay as Android.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            webView.createPDF { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let data):
                    self.finish(.success(data))
                case .failure(let error):
                    self.finish(.failure(error))
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        webView?.navigationDelegate = nil
        webView = nil
        continuation.resume(with: result)
    }
}
